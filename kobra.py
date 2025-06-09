import os
import json
import re
import logging
import subprocess
import paho.mqtt.client as paho
import shutil
import asyncio

from ..utils import Sentinel
from .power import PowerDevice


class Kobra:

    _total_layer = 0

    def __init__(self, config):
        self.server = config.get_server()
        self.power = self.server.load_component(self.server.config, 'power')

        # Monkey patch Moonraker for Kobra
        logging.info('Starting Kobra patching...')

        self.patch_status_updates()
        self.patch_network_interfaces()
        self.patch_spoolman()
        self.patch_simplyprint()
        self.patch_mqtt_print()
        self.patch_bed_mesh()
        self.patch_objects_list()
        self.patch_mainsail()
        self.patch_k2p_bug()

        logging.info('Completed Kobra patching! Yay!')

    async def component_init(self):
      pass

    def patch_status(self, status):
        if 'print_stats' in status:
            if 'state' in status['print_stats']:
                # Convert Kobra state
                state = status['print_stats']['state']
                logging.info(f'[Kobra] Converted Kobra state {state}')

                if state.lower() == 'heating':
                    state = 'printing'
                if state.lower() == 'leveling':
                    state = 'printing'
                if state.lower() == 'resonance':
                    state = 'printing'
                if state.lower() == 'onpause':
                    state = 'paused'

                status['print_stats']['state'] = state

                # Inject in 'idle_timeout' for Fluidd
                if 'idle_timeout' not in status:
                    status['idle_timeout'] = {}

                status['idle_timeout']['state'] = state

            if 'filename' in status['print_stats']:
                # Remove path prefix from filename
                status['print_stats']['filename'] = status['print_stats']['filename'].replace('/useremain/app/gk/gcodes/', '')

        if 'virtual_sdcard' in status:
            if 'total_layer' in status['virtual_sdcard']:
                # Save layer count for later
                self._total_layer = status['virtual_sdcard']['total_layer']

            if 'current_layer' in status['virtual_sdcard']:
                current_layer = status['virtual_sdcard']['current_layer']

                # Inject current and total layer count in 'info' for Mainsail / Fluidd
                if 'print_stats' not in status:
                    status['print_stats'] = {}
                if 'info' not in status['print_stats']:
                    status['print_stats']['info'] = {}

                status['print_stats']['info']['current_layer'] = current_layer
                status['print_stats']['info']['total_layer'] = self._total_layer

            if 'file_path' in status['virtual_sdcard']:
                # Remove path prefix from file path
                status['virtual_sdcard']['file_path'] = status['virtual_sdcard']['file_path'].replace('/useremain/app/gk/gcodes/', '')

        return status


    def patch_status_updates(self):
        from .klippy_apis import KlippyAPI
        from .klippy_connection import KlippyConnection, KlippyRequest

        logging.info('> Hooking status change...')

        def wrap__send_klippy_request(original__send_klippy_request):
            async def _send_klippy_request(me, method, params, default = Sentinel.MISSING, transport = None):
                result = await original__send_klippy_request(me, method, params, default, transport)
                if result and isinstance(result, dict) and 'status' in result:
                    result['status'] = self.patch_status(result['status'])
                return result
            return _send_klippy_request

        def wrap_send_status(original_send_status):
            def send_status(me, status, eventtime):
                status = self.patch_status(status)
                return original_send_status(me, status, eventtime)
            return send_status

        logging.debug(f'  Before: {KlippyAPI._send_klippy_request}')
        setattr(KlippyAPI, '_send_klippy_request', wrap__send_klippy_request(KlippyAPI._send_klippy_request))
        logging.debug(f'  After: {KlippyAPI._send_klippy_request}')

        logging.debug(f'  Before: {KlippyAPI.send_status}')
        setattr(KlippyAPI, 'send_status', wrap_send_status(KlippyAPI.send_status))
        logging.debug(f'  After: {KlippyAPI.send_status}')

        def wrap__process_status_update(original__process_status_update):
            def _process_status_update(me, eventtime, status):
                status = self.patch_status(status)
                return original__process_status_update(me, eventtime, status)
            return _process_status_update

        logging.debug(f'  Before: {KlippyConnection._process_status_update}')
        setattr(KlippyConnection, '_process_status_update', wrap__process_status_update(KlippyConnection._process_status_update))
        logging.debug(f'  After: {KlippyConnection._process_status_update}')

        klippy_connection = self.server.lookup_component("klippy_connection")
        klippy_connection.unregister_method('process_status_update')
        klippy_connection.register_remote_method('process_status_update', klippy_connection._process_status_update, need_klippy_reg=False)

        def wrap_set_result(original_set_result):
            def set_result(me, result):
                if isinstance(result, dict) and 'status' in result:
                    result['status'] = self.patch_status(result['status'])
                original_set_result(me, result)
            return set_result

        logging.debug(f'  Before: {KlippyRequest.set_result}')
        setattr(KlippyRequest, 'set_result', wrap_set_result(KlippyRequest.set_result))
        logging.debug(f'  After: {KlippyRequest.set_result}')

    def patch_network_interfaces(self):
        from .machine import Machine

        async def _parse_network_interfaces(me, sequence: int, notify: bool = True):
            logging.debug('[Kobra] Skipping call')
            return

        logging.info('> Disable network interfaces parsing...')

        logging.debug(f'  Before: {Machine._parse_network_interfaces}')
        setattr(Machine, '_parse_network_interfaces', _parse_network_interfaces)
        logging.debug(f'  After: {Machine._parse_network_interfaces}')

    def patch_spoolman(self):
        from .spoolman import SpoolManager

        def wrap_set_active_spool(original_set_active_spool):
            def set_active_spool(me, spool_id = None, SPOOL_ID = None):
                if spool_id is None:
                    logging.info('[Kobra] Injected SPOOL_ID')
                    spool_id = int(SPOOL_ID)
                return original_set_active_spool(me, spool_id)
            return set_active_spool

        logging.info('> Allowing SPOOL_ID parameter...')

        logging.debug(f'  Before: {SpoolManager.set_active_spool}')
        setattr(SpoolManager, 'set_active_spool', wrap_set_active_spool(SpoolManager.set_active_spool))
        logging.debug(f'  After: {SpoolManager.set_active_spool}')

    def patch_simplyprint(self):
        from ..server import Server

        def wrap_get_klippy_info(original_get_klippy_info):
            def get_klippy_info(me):
                result = original_get_klippy_info(me)
                result['klipper_path'] = '/opt'
                logging.info('[Kobra] Injected klipper_path')
                return result
            return get_klippy_info

        logging.info('> Fix Simplyprint crash...')

        logging.debug(f'  Before: {Server.get_klippy_info}')
        setattr(Server, 'get_klippy_info', wrap_get_klippy_info(Server.get_klippy_info))
        logging.debug(f'  After: {Server.get_klippy_info}')

    def patch_mqtt_print(self):
        from .klippy_apis import KlippyAPI

        def wrap_run_gcode(original_run_gcode):
            async def run_gcode(me, script, default = Sentinel.MISSING):
                if script.startswith('SDCARD_PRINT_FILE'):
                    self._total_layer = 0
                    filename = re.search("FILENAME=\"([^\"]+)\"$", script)
                    filename = filename[1] if filename else None
                return await original_run_gcode(me, script, default)
            return run_gcode

        logging.info('> Send prints to MQTT...')

        logging.debug(f'  Before: {KlippyAPI.run_gcode}')
        setattr(KlippyAPI, 'run_gcode', wrap_run_gcode(KlippyAPI.run_gcode))
        logging.debug(f'  After: {KlippyAPI.run_gcode}')

    def patch_bed_mesh(self):
        from .klippy_connection import KlippyConnection

        def wrap_request(original_request):
            async def request(me, web_request):
                rpc_method = web_request.get_endpoint()
                if rpc_method == "gcode/script":
                    script = web_request.get_str('script', "")
                    if script.lower() == "bed_mesh_map" and os.path.isfile("/home/printerpi/printer_data/config/printer_mutable.cfg"):
                        logging.info('[Kobra] Injected bed mesh')
                        with open("/home/printerpi/printer_data/config/printer_mutable.cfg", "r") as f:
                            config = json.load(f)
                            mesh = config.get("bed_mesh default")
                            if not mesh is None:
                                points = json.loads("[[" + mesh.get('points').replace("\n", "], [") + "]]")
                                return "mesh_map_output " + json.dumps({
                                    "mesh_min": (float(mesh.get('min_x')), float(mesh.get('min_y'))),
                                    "mesh_max": (float(mesh.get('max_x')), float(mesh.get('max_y'))),
                                    "z_positions": points
                                })
                            else:
                                raise self.server.error("Failed to open mesh")
                    elif script.lower().startswith("bed_mesh_calibrate"):
                        logging.info('[Kobra] Injected bed mesh calibration script')
                        web_request.get_args()["script"] = "MOVE_HEAT_POS\nM109 S140\nWIPE_NOZZLE\nBED_MESH_CALIBRATE\nSAVE_CONFIG"
                    elif script.lower().startswith('bed_mesh_profile'):
                        name = re.search('save=(\"(?:[^\"]+)\"|(?:[^\s]+))', script.lower())
                        if name and name[1] != 'default':
                            message = 'GoKlipper only support one default bed mesh'
                            logging.error(message)
                            raise self.server.error(message)
                return await original_request(me, web_request)
            return request

        def wrap__request_standard(original__request_standard):
            async def _request_standard(me, web_request, timeout = None):
                args = web_request.get_args()

                # Do not send bed_mesh to goklipper, it does not support it
                want_bed_mesh = False
                if 'objects' in args and 'bed_mesh' in args['objects']:
                    want_bed_mesh = True
                    del args['objects']['bed_mesh']
                if 'objects' in args and 'bed_mesh \"default\"' in args['objects']:
                    want_bed_mesh = True
                    del args['objects']['bed_mesh \"default\"']

                result = await original__request_standard(me, web_request, timeout)

                # Add bed_mesh, so mainsail will recognize it
                if want_bed_mesh:
                    if 'status' not in result:
                        result['status'] = {}

                    result['status']['bed_mesh'] = {}
                    result['status']['bed_mesh \"default\"'] = {}

                    if os.path.isfile("/home/printerpi/printer_data/config/printer_mutable.cfg"):
                        with open('/home/printerpi/printer_data/config/printer_mutable.cfg', 'r') as f:
                            config = json.load(f)
                            mesh = config.get('bed_mesh default')
                            if not mesh is None:
                                points = json.loads("[[" + mesh.get('points').replace("\n", "], [") + "]]")

                                result['status']['bed_mesh'] = {
                                    "profile_name": "default",
                                    "mesh_min": (float(mesh.get("min_x")), float(mesh.get("min_y"))),
                                    "mesh_max": (float(mesh.get("max_x")), float(mesh.get("max_y"))),
                                    "probed_matrix": points,
                                    "mesh_matrix": points
                                }
                                result['status']['bed_mesh \"default\"'] = {
                                    "points": points,
                                    "mesh_params": {
                                        "min_x": float(mesh["min_x"]),
                                        "max_x": float(mesh["max_x"]),
                                        "min_y": float(mesh["min_y"]),
                                        "max_y": float(mesh["max_y"]),
                                        "x_count": int(mesh["x_count"]),
                                        "y_count": int(mesh["y_count"]),
                                        "mesh_x_pps": int(mesh["mesh_x_pps"]),
                                        "mesh_y_pps": int(mesh["mesh_y_pps"]),
                                        "tension": float(mesh["tension"]),
                                        "algo": mesh["algo"]
                                    }
                                }
                return result
            return _request_standard

        logging.info('> Adding Kobra bed mesh support...')

        logging.debug(f'  Before: {KlippyConnection.request}')
        setattr(KlippyConnection, 'request', wrap_request(KlippyConnection.request))
        logging.debug(f'  After: {KlippyConnection.request}')

        logging.debug(f'  Before: {KlippyConnection._request_standard}')
        setattr(KlippyConnection, '_request_standard', wrap__request_standard(KlippyConnection._request_standard))
        logging.debug(f'  After: {KlippyConnection._request_standard}')

    def patch_objects_list(self):
        from .klippy_connection import KlippyConnection

        def wrap_request(original_request):
            async def request(me, web_request):
                rpc_method = web_request.get_endpoint()
                if rpc_method == "objects/list":
                    logging.info('[Kobra] Injected objects list')
                    return {
                        "objects": [
                            "motion_report",
                            "gcode_macro pause",
                            "gcode_macro resume",
                            "gcode_macro cancel_print",
                            "gcode_macro t0",
                            "gcode_macro t1",
                            "gcode_macro t2",
                            "gcode_macro t3",
                            "configfile",
                            "heaters",
                            "respond",
                            "display_status",
                            "extruder",
                            "fan",
                            "gcode_move",
                            "heater_bed",
                            "mcu",
                            "mcu nozzle_mcu",
                            "ota_filament_hub",
                            "pause_resume",
                            "pause_resume/cancel",
                            "print_stats",
                            "toolhead",
                            "verify_heater extrude",
                            "verify_heater heater_bed",
                            "virtual_sdcard",
                            "webhooks",
                            "bed_mesh",
                            "bed_mesh \"default\"",
                            "idle_timeout"
                        ]
                    }
                return await original_request(me, web_request)
            return request

        logging.info('> Patching objects/list call...')

        logging.debug(f'  Before: {KlippyConnection.request}')
        setattr(KlippyConnection, 'request', wrap_request(KlippyConnection.request))
        logging.debug(f'  After: {KlippyConnection.request}')

    def patch_mainsail(self):
        from .klippy_connection import KlippyConnection

        def wrap__request_standard(original__request_standard):
            async def _request_standard(me, web_request, timeout = None):
                result = await original__request_standard(me, web_request, timeout)
                if 'status' in result and 'configfile' in result['status'] and 'config' in result['status']['configfile']:
                    logging.info('[Kobra] Injected Mainsail macros')
                    result['status']['configfile']['config']['gcode_macro pause'] = {}
                    result['status']['configfile']['config']['gcode_macro resume'] = {}
                    result['status']['configfile']['config']['gcode_macro cancel_print'] = {}
                return result
            return _request_standard

        logging.info('> Patching Mainsail macros...')

        logging.debug(f'  Before: {KlippyConnection._request_standard}')
        setattr(KlippyConnection, '_request_standard', wrap__request_standard(KlippyConnection._request_standard))
        logging.debug(f'  After: {KlippyConnection._request_standard}')

    def patch_k2p_bug(self):
        from .klippy_apis import KlippyAPI

        def wrap_get_klippy_info(original_get_klippy_info):
            async def get_klippy_info(me, send_id, default = Sentinel.MISSING):
                result = await original_get_klippy_info(me)
                result['klipper_path'] = '/opt'
                result['python_path'] = ''
                logging.info('[Kobra] Injected missing paths')
                return result
            return get_klippy_info

        logging.info('> Fix K2P startup bug...')

        logging.debug(f'  Before: {KlippyAPI.get_klippy_info}')
        setattr(KlippyAPI, 'get_klippy_info', wrap_get_klippy_info(KlippyAPI.get_klippy_info))
        logging.debug(f'  After: {KlippyAPI.get_klippy_info}')


class ShellPowerDevice(PowerDevice):
    def __init__(self, config):
        super().__init__(config)
        self.power_on_command = config.get('power_on_command', None)
        if not self.power_on_command:
            raise config.error(f"Option 'power_on_command' in section [{config.get_name()}] must be set")
        self.power_off_command = config.get('power_off_command', None)
        if not self.power_off_command:
            raise config.error(f"Option 'power_off_command' in section [{config.get_name()}] must be set")
        self.get_state_command = config.get('get_state_command', None)
        self.state = config.get('default_state', None)

    async def init_state(self):
        await self.refresh_status()

    async def refresh_status(self):
        if not self.get_state_command:
            return

        try:
            command = self.get_state_command
            result = subprocess.check_output(['sh', '-c', command])
            result = result.decode('utf-8').strip()
            logging.debug(f'ShellPowerDevice "{command}" => "{result}"')

            previous_state = self.state

            if result and (result == '1' or str(result).lower() == 'true' or str(result).lower() == 'on'):
                self.state = 'on'
            else:
                self.state = 'off'

            if previous_state != self.state:
                logging.info(f'ShellPowerDevice {self.name} is now {self.state}')
                self.notify_power_changed()
        except:
            logging.exception(f"ShellPowerDevice error: {self.name}")

    async def set_power(self, state):
        if not self.get_state_command:
            self.state = state

        state = int(state == "on")

        try:
            command = self.power_on_command if state else self.power_off_command
            result = subprocess.check_output(['sh', '-c', command])
            result = result.decode('utf-8').strip()
            logging.debug(f'ShellPowerDevice "{command}" => "{result}"')
        except:
            logging.exception(f"ShellPowerDevice error: {self.name}")

        await self.refresh_status()



def load_component(config):
    return Kobra(config)
