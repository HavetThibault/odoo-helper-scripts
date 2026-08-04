#!/usr/bin/env python3

import logging
import subprocess
import sys

origin_logger_get_logger = logging.getLogger
origin_logger_set_level = logging.Logger.setLevel
origin_logger_init = logging.Logger.__init__
origin_logger_format = logging.Formatter.format

LEVELS = ('INFO', 'WARNING', 'ERROR', 'CRITICAL')
LEVEL_BY_NAME = {name: getattr(logging, name, logging.INFO) for name in LEVELS}
IS_TESTING = '--test-tags' in sys.argv



""" CONFIG VARIABLES """

SHOW_ALL_LOGS_AGAIN = False

PROGRESS_BAR_LENGTH = 50

DISPLAYED_RECORD_NAMES = ('odoo.service.server', 'odoo.tests.stats', 'odoo.tests.result', 'odoo.service.server.ThreadedServer')
DISPLAYED_RECORD_NAMES_COND = {
    'odoo': lambda record: record.msg.startswith('Odoo version %s'),
    'odoo.modules.loading': lambda record: record.msg.startswith('%s modules loaded in ') and record.args[2] > 1,
}

def tests_ended_callback():
    subprocess.run('notify-send -t 1300 -i face-smile -u normal "The Tests Ended" "DONE"', shell=True, executable="/bin/bash")

def web_server_ready_callback():
    subprocess.run('notify-send -t 1300 -i face-smile -u normal "Web Server Ready" "READY"', shell=True, executable="/bin/bash")

""" END OF CONFIG VARIABLES """



if not SHOW_ALL_LOGS_AGAIN:

    class ProgressNotifFormatterExtension:
        def __init__(self):
            self.first_loaded_module_nbr = None
            self.to_load_module_nbr = None
            self.previous_msg_len = None
            self.was_last_message_module_loading = False

        def get_format(self):

            def format(formatter, record):
                if module_loading := record.name == 'odoo.modules.loading' and record.msg.startswith('Loading module %s'):
                    loaded_modules = record.args[1]
                    total_modules = record.args[2]
                    # 'loaded_modules' starts at 1 and ends at 'total_modules'
                    if self.first_loaded_module_nbr is None:
                        self.first_loaded_module_nbr = loaded_modules
                        self.to_load_module_nbr = total_modules - loaded_modules
                    real_loaded_modules = loaded_modules - self.first_loaded_module_nbr
                    progress_value = int(real_loaded_modules / self.to_load_module_nbr * PROGRESS_BAR_LENGTH)
                    msg = (f'[{'=' * progress_value}{'-' * (PROGRESS_BAR_LENGTH - progress_value)}]  '
                        f'{loaded_modules}/{total_modules}  Loading {record.args[0]}')
                else:
                    msg = origin_logger_format(formatter, record)

                msg_len = len(msg)
                if self.was_last_message_module_loading:
                    msg = f'\033[A\r{msg}'.ljust(self.previous_msg_len + 4, " ")
                if module_loading:
                    self.previous_msg_len = msg_len
                self.was_last_message_module_loading = module_loading
                return msg

            return format


    class PleaseFilterImportantLogsDearGodooFilter(logging.Filter):
        fired_end_notification = False

        def __init__(self, min_log_level, logger):
            super().__init__()
            self.min_log_level = min_log_level
            self.logger = logger

        def filter(self, record):
            filter = self
            while not filter.min_log_level and filter.logger.parent:
                filter = filter.logger.parent.please_filter
            min_log_level = filter.min_log_level
            if not self.fired_end_notification:
                if IS_TESTING and record.name == 'odoo.tests.result':
                    tests_ended_callback()
                    self.fired_end_notification = True
                elif not IS_TESTING and record.name == 'odoo.registry' and record.msg.startswith('Registry loaded in '):
                    web_server_ready_callback()
                    self.fired_end_notification = True

            return ((record.levelname not in LEVEL_BY_NAME or LEVEL_BY_NAME[record.levelname] >= min_log_level)
                or record.name in DISPLAYED_RECORD_NAMES
                or (record.name in DISPLAYED_RECORD_NAMES_COND and (DISPLAYED_RECORD_NAMES_COND[record.name])(record))
                or record.name == 'odoo.modules.loading' and record.msg.startswith('Loading module %s') and record.args[2] > 1
            )

    # This root logger is created by default when loading the logging library, we have to give him the custom filter like the other future loggers !
    root_logger = logging.getLogger('root')
    root_logger.please_filter = PleaseFilterImportantLogsDearGodooFilter(root_logger.level, root_logger)
    root_logger.addFilter(root_logger.please_filter)

    INFO_LEVEL = getattr(logging, 'INFO', logging.INFO)


    # Setting the logger level should also update the level of the related filter
    def please_filter_set_level(self: logging.Logger, level):
        self.please_filter.min_log_level = level
        origin_logger_set_level(self, min(INFO_LEVEL, level))


    def please_filter_logger_init(self: logging.Logger, name, level=logging.NOTSET):
        origin_logger_init(self, name, level)
        self.please_filter = PleaseFilterImportantLogsDearGodooFilter(level, self)
        self.addFilter(self.please_filter)
        origin_logger_set_level(self, min(level, INFO_LEVEL))


    logging.Logger.setLevel = please_filter_set_level
    logging.Logger.__init__ = please_filter_logger_init
    logging.Formatter.format = ProgressNotifFormatterExtension().get_format()


import odoo.cli

if __name__ == "__main__":
    odoo.cli.main()
