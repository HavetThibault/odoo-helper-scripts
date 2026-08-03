#!/usr/bin/env python3


""" CONFIG VARIABLES """

SHOW_ALL_LOGS_AGAIN = False
SHOW_NOTIFICATION_ON_TEST_END = True
OPEN_CHROME_ON_WEB_SERVER_READY = True
SHOW_NOTIFICATION_ON_WEB_SERVER_READY = True
PROGRESS_BAR_LENGTH = 50

DISPLAYED_RECORD_NAMES = ('odoo.service.server', 'odoo.tests.stats', 'odoo.tests.result', 'odoo.service.server.ThreadedServer')
DISPLAYED_RECORD_NAMES_COND = {
    'odoo': lambda record: record.msg.startswith('Odoo version %s'),
    'odoo.modules.loading': lambda record: record.msg.startswith('%s modules loaded in ') and record.args[2] > 1,
}

cursor_go_up_char = '\033[A'
carriage_return_char = '\r'

""" END OF CONFIG VARIABLES """


import logging
import subprocess
import sys
import threading
from selenium import webdriver
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By


origin_logger_get_logger = logging.getLogger
origin_logger_set_level = logging.Logger.setLevel
origin_logger_init = logging.Logger.__init__
origin_logger_format = logging.Formatter.format

LEVELS = ('INFO', 'WARNING', 'ERROR', 'CRITICAL')
LEVEL_BY_NAME = {name: getattr(logging, name, logging.INFO) for name in LEVELS}
IS_TESTING = '--test-tags' in sys.argv
IS_SHELL = 'shell' in sys.argv


LOGIN = ''
PASSWORD = ''
SHOW_CHROME = True
i = 0
while i < len(sys.argv):
    if sys.argv[i] == '--login':
        if len(sys.argv) <= i + 1 or sys.argv[i + 1].startswith('-'):
            raise Exception('Expected login after --login')
        sys.argv.pop(i)
        LOGIN = sys.argv.pop(i)
        i -= 1
    elif sys.argv[i] == '--password':
        if len(sys.argv) <= i + 1 or sys.argv[i + 1].startswith('-'):
            raise Exception('Expected login after --password')
        sys.argv.pop(i)
        PASSWORD = sys.argv.pop(i)
        i -= 1
    elif sys.argv[i] == '-nc':
        SHOW_CHROME = False
        sys.argv.pop(i)
        i -= 1
    i += 1


def _open_browser():
    # You have to set the login=admin in the query string to get the focus on the form, otherwise you'll get the following error:
    # selenium.common.exceptions.ElementNotInteractableException: Message: element not interactable
    if LOGIN == '' or PASSWORD == '':
        raise Exception('Expected a login and a password passed through the arguments!')
    driver.get(f"http://localhost:8069/web/login?login={LOGIN}")
    password = driver.find_element(By.ID, "password")
    password.send_keys(PASSWORD)
    password.send_keys(Keys.RETURN)

if not IS_TESTING and not IS_SHELL and OPEN_CHROME_ON_WEB_SERVER_READY and SHOW_CHROME:
    # webbrowser didn't work
    # os.system('chrome') didn't work
    # subprocess.Popen(['google-chrome', url], ...) didn't work
    # So I used Selenium from a thread
    driver = webdriver.Chrome()
    thread = threading.Thread(target=_open_browser, daemon=True)

def web_server_ready_callback():
    if not IS_SHELL and OPEN_CHROME_ON_WEB_SERVER_READY and SHOW_CHROME:
        thread.start()
    elif SHOW_NOTIFICATION_ON_WEB_SERVER_READY:
        subprocess.Popen('notify-send --transient --icon info --urgency normal "Web Server Ready" "READY"',
            shell=True, executable="/bin/bash")

def tests_ended_callback(odoo_test_result):
    if not SHOW_NOTIFICATION_ON_TEST_END:
        return
    errors = odoo_test_result.errors_count
    failures = odoo_test_result.failures_count
    testRun = odoo_test_result.testsRun
    test_header = 'PASSED' if errors + failures == 0 else 'FAILED'
    subprocess.Popen(f'notify-send --transient --icon info --urgency normal "The Tests {test_header}" "{failures} failed, {errors} error(s) of {testRun} tests"',
        shell=True, executable="/bin/bash")


if not SHOW_ALL_LOGS_AGAIN:
    """
        HOW IT WORKS:
        -------------

        For each newly created logger:
            If the logger level (the level threshold below which logs aren't displayed) is higher than `logging.INFO`, then the level of the logger is set back to the `logging.INFO`
            Then we attach a `PleaseFilterImportantLogsDearGodooFilter` to this logger, and this filter will only keep the logs with a higher or equal level to the original logger level (stored in `min_log_level`), OR the "important logs"

        If the filter `min_log_level` is 0, this filter will iterate through the loggers hierarchy until it finds a logger with a non zero `min_log_level` filter and use this threshold instead (see `PleaseFilterImportantLogsDearGodooFilter.filter`).

        The progress bar is displayed by overwriting the `logging.Formatter.format` method.
        The end of tests/server ready callables (notification) are managed in the `PleaseFilterImportantLogsDearGodooFilter`.
    """

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
                    msg = f'{cursor_go_up_char}{carriage_return_char}{msg}'.ljust(self.previous_msg_len + 4, " ")
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
                    tests_ended_callback(record.args[0])
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
