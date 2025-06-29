#!/bin/bash

# A bash script to preprocess and merge INI-style configuration files.
# This script mimics the functionality of a Python script, including
# handling of [include ...], section/key overrides with '!', and multi-line values.
# This version has been optimized for speed by removing process-heavy operations
# like `sed` and `eval` from loops, using Bash namerefs instead.

# --- Global State ---

# Associative array to hold the final resolved key-value pairs.
# Keys are "mangled" as "section_name_||_key_name" to simulate a nested dictionary.
declare -A RESOLVED_CONFIG

# Indexed array to maintain the order of sections for the final output.
declare -a SECTION_ORDER

# Associative array to map a section name to the *name* of the array holding its key order.
# This avoids slow serialization and is key to the performance optimization.
declare -A KEY_ORDER_MAP

# Associative array to prevent circular dependencies during file includes.
declare -A PROCESSED_INCLUDES

# Counter for creating unique array names for key ordering.
declare -i __key_order_counter=0


# --- Helper Functions ---

# remove_element_from_array(element, array_name_as_string)
# Removes a given element from an indexed array passed by name reference.
# Usage: remove_element_from_array "element_to_remove" "my_array"
function remove_element_from_array() {
    local element_to_remove="$1"
    local -n array_ref="$2" # Use nameref for indirect array modification
    local new_array=()
    for item in "${array_ref[@]}"; do
        if [[ "$item" != "$element_to_remove" ]]; then
            new_array+=("$item")
        fi
    done
    array_ref=("${new_array[@]}")
}

# add_section_to_order(section_name)
# Adds a section to the global SECTION_ORDER array if it's not already present.
function add_section_to_order() {
    local section_name="$1"
    local found=0
    for item in "${SECTION_ORDER[@]}"; do
        if [[ "$item" == "$section_name" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        SECTION_ORDER+=("$section_name")
    fi
}


# --- Core Logic ---

# process_file(path, hint_path)
# Recursively reads a file, processes its lines, and expands includes.
# This function uses a state machine to parse the INI structure.
function process_file() {
    local path="$1"
    local hint_path="$2"
    local corrected_path="$path"

    # --- 1. Resolve the path to the configuration file ---
    if [[ ! "$path" = /* ]]; then # If not an absolute path
        if [[ -n "$hint_path" && -f "$hint_path/$path" ]]; then
            # Check relative to the directory of the file that included it
            corrected_path="$hint_path/$path"
        elif [[ -f "$(realpath "$path" 2>/dev/null)" ]]; then
            # Check relative to the current working directory
            corrected_path="$(realpath "$path")"
        fi
    fi

    if [[ ! -f "$corrected_path" ]]; then
        echo "Could not find file \"$path\", skipping content..." >&2
        return
    fi

    # --- 2. Prevent circular includes ---
    local real_path
    real_path="$(realpath "$corrected_path")"
    if [[ -n "${PROCESSED_INCLUDES[$real_path]}" ]]; then
        echo "Circular include detected for \"$real_path\", skipping." >&2
        return
    fi
    PROCESSED_INCLUDES["$real_path"]=1

    # --- 3. Parse the file line-by-line ---
    local current_section=""
    local current_key=""
    local current_value=""

    # Helper function to commit the previously parsed key-value pair to the global config
    commit_kv() {
        if [[ -z "$current_section" || -z "$current_key" ]]; then
            current_key=""
            current_value=""
            return
        fi

        # Get a nameref to the key order array for the current section
        local -n key_order_arr_ref="${KEY_ORDER_MAP[$current_section]}"

        # Handle key removal, e.g., !my_key: ...
        if [[ "$current_key" == !* ]]; then
            local key_to_remove="${current_key:1}"
            shopt -s extglob
            key_to_remove="${key_to_remove##*( )}" # lstrip whitespace
            shopt -u extglob

            # Unset the value
            unset "RESOLVED_CONFIG[${current_section}_||_${key_to_remove}]"

            # Remove the key from the order tracking array directly via nameref
            local new_order_arr=()
            for k in "${key_order_arr_ref[@]}"; do
                if [[ "$k" != "$key_to_remove" ]]; then
                    new_order_arr+=("$k")
                fi
            done
            key_order_arr_ref=("${new_order_arr[@]}")

        else
            # Add or overwrite the key-value pair
            RESOLVED_CONFIG["${current_section}_||_${current_key}"]="$current_value"

            # Add key to order tracking if it's not already there
            local found=0
            for item in "${key_order_arr_ref[@]}"; do
                if [[ "$item" == "$current_key" ]]; then
                    found=1
                    break
                fi
            done

            if [[ $found -eq 0 ]]; then
                key_order_arr_ref+=("$current_key")
            fi
        fi

        # Reset for the next key-value pair
        current_key=""
        current_value=""
    }

    # Read file line by line, preserving leading/trailing whitespace.
    # The `|| [[ -n "$line" ]]` ensures the last line is processed even if it lacks a newline.
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Case 1: A section header, e.g., [my_section]
        if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
            commit_kv # Commit the last key-value from the previous section
            local section_header="${BASH_REMATCH[1]}"

            # Case 1a: An include directive, e.g., [include other.cfg]
            if [[ "$section_header" =~ ^include[[:space:]]+(.+)$ ]]; then
                local include_path="${BASH_REMATCH[1]}"
                # Recursively process the included file, using its own location as the hint path
                process_file "$include_path" "$(dirname "$real_path")"
                current_section="" # Reset section context after include

            # Case 1b: A section removal directive, e.g., [!my_section]
            elif [[ "$section_header" == !* ]]; then
                local section_to_remove="${section_header:1}"
                remove_element_from_array "$section_to_remove" "SECTION_ORDER"
                # Remove all keys associated with this section
                for key in "${!RESOLVED_CONFIG[@]}"; do
                    if [[ "$key" == "${section_to_remove}_||_"* ]]; then
                        unset "RESOLVED_CONFIG[$key]"
                    fi
                done
                # Also remove its key order tracking
                unset KEY_ORDER_MAP["$section_to_remove"]
                current_section="" # Ignore content until the next valid section

            # Case 1c: A regular section header
            else
                current_section="$section_header"
                add_section_to_order "$current_section"
                # If we haven't seen this section before, create a new array to hold its key order
                if [[ ! -v "KEY_ORDER_MAP[$current_section]" ]]; then
                    local key_order_array_name="__key_order_${__key_order_counter}"
                    ((__key_order_counter++))
                    declare -g -a "$key_order_array_name" # Create the array globally
                    KEY_ORDER_MAP["$current_section"]="$key_order_array_name"
                fi
            fi

        # Case 2: A key-value pair, e.g., my_key: my_value
        elif [[ -n "$current_section" && "$line" =~ ^([^:]+):(.*)$ ]]; then
            commit_kv # Commit the previous key-value pair
            current_key="${BASH_REMATCH[1]}"
            shopt -s extglob
            current_key="${current_key##*( )}" # lstrip whitespace from key
            shopt -u extglob
            current_value="${BASH_REMATCH[2]}"

        # Case 3: A continuation of a multi-line value
        elif [[ -n "$current_key" ]]; then
            current_value+=$'\n'"$line"
        fi
    done < "$corrected_path"

    # Commit the very last key-value pair after the loop finishes for the file
    commit_kv

    # Unset the circular dependency flag, allowing this file to be included again elsewhere
    unset PROCESSED_INCLUDES["$real_path"]
}

# print_resolved_config()
# Prints the final, merged configuration in INI format to standard output.
function print_resolved_config() {
    # Print a header similar to the original script's output
    echo '# This file is generated automatically'
    echo '# To modify its content, please use the source configuration files instead'
    echo ''

    # Iterate through sections in the order they were defined to maintain structure
    for section_name in "${SECTION_ORDER[@]}"; do
        # Check if the section still exists and has an order map
        if [[ ! -v "KEY_ORDER_MAP[$section_name]" ]]; then
            continue
        fi

        # Get a nameref to the array holding the key order for this section
        local -n keys_for_section="${KEY_ORDER_MAP[$section_name]}"

        # Also skip if, after overrides, the section has no keys left
        if [[ ${#keys_for_section[@]} -eq 0 ]]; then
            continue
        fi

        echo "[$section_name]"

        for key in "${keys_for_section[@]}"; do
            local mangled_key="${section_name}_||_${key}"
            # Check if the key still exists in the resolved config (it might have been removed)
            if [[ -v RESOLVED_CONFIG[$mangled_key] ]]; then
                local value="${RESOLVED_CONFIG[$mangled_key]}"

                # Trim trailing whitespace (spaces, tabs, newlines) from the value before printing.
                shopt -s extglob
                value="${value%%+([[:space:]])}"
                shopt -u extglob

                echo "${key}:${value}"
            fi
        done
        echo ""
    done
}

# --- Main Execution ---
function main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <source_config_file_1> [source_config_file_2] ..." >&2
        exit 1
    fi

    # Process all source configuration files provided as command-line arguments
    for source_file in "$@"; do
        process_file "$source_file" "$(pwd)"
    done

    # Print the final result to standard output
    print_resolved_config
}

# Run the main function, passing all command-line arguments to it
main "$@"
