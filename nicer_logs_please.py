#!/usr/bin/env python3


""" CONFIG VARIABLES """

SHOW_ALL_LOGS_AGAIN = False
SHOW_NOTIFICATION_ON_TEST_END = True
OPEN_CHROME_ON_WEB_SERVER_READY = True
SHOW_NOTIFICATION_ON_WEB_SERVER_READY = True
PROGRESS_BAR_LENGTH = 50
ODOO_URL_START='http://localhost:8069/'

DISPLAYED_RECORD_NAMES = ('odoo.service.server', 'odoo.tests.stats', 'odoo.tests.result', 'odoo.service.server.ThreadedServer')
DISPLAYED_RECORD_NAMES_COND = {
    'odoo': lambda record: record.msg.startswith('Odoo version %s'),
    'odoo.modules.loading': lambda record: record.msg.startswith('%s modules loaded in ') and record.args[2] > 1,
}

cursor_go_up_char = '\033[A'
carriage_return_char = '\r'
CHROME_DEBUG_PORT=11212

""" END OF CONFIG VARIABLES """

import logging
import subprocess
import sys
import os
import threading
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.wait import WebDriverWait
import requests

origin_logger_get_logger = logging.getLogger
origin_logger_set_level = logging.Logger.setLevel
origin_logger_init = logging.Logger.__init__
origin_logger_format = logging.Formatter.format

LEVELS = ('INFO', 'WARNING', 'ERROR', 'CRITICAL')
LEVEL_BY_NAME = {name: getattr(logging, name, logging.INFO) for name in LEVELS}
IS_TESTING = '--test-tags' in sys.argv
IS_SHELL = 'shell' in sys.argv

OPEN_CHROME_WAIT = object()
LOGIN = ''
PASSWORD = ''
SHOW_CHROME = True
i = 0
while i < len(sys.argv):
    match sys.argv[i]:
        case '--login':
            if len(sys.argv) <= i + 1 or sys.argv[i + 1].startswith('-'):
                raise Exception('Expected login after --login')
            sys.argv.pop(i)
            LOGIN = sys.argv.pop(i)
            i -= 1
        case '--password':
            if len(sys.argv) <= i + 1 or sys.argv[i + 1].startswith('-'):
                raise Exception('Expected login after --password')
            sys.argv.pop(i)
            PASSWORD = sys.argv.pop(i)
            i -= 1
        case '-nc':
            SHOW_CHROME = False
            sys.argv.pop(i)
            i -= 1
    i += 1

# The ID of the tab that has the url of Odoo
is_chrome_opened = False
# Whether there is a Chrome running, but that no tab has the url of Odoo
new_window = False
if not IS_SHELL and not IS_TESTING and OPEN_CHROME_ON_WEB_SERVER_READY and SHOW_CHROME:
    try:
        response = requests.get(f"http://localhost:{CHROME_DEBUG_PORT}/json")
        is_chrome_opened = True
    except requests.exceptions.RequestException:
        profile_dir = 'Profile 1'
        user_data_dir = os.path.expanduser("~/.config/google-chrome-remote")
        subprocess.Popen(["google-chrome", f"--remote-debugging-port={CHROME_DEBUG_PORT}", f"--user-data-dir={user_data_dir}",
            f"--profile-directory={profile_dir}", "--log-level=3"],
            start_new_session=True)

    chrome_options = Options()
    chrome_options.add_argument(f"--remote-debugging-port={CHROME_DEBUG_PORT}")  # Enable debugging
    chrome_options.add_experimental_option("debuggerAddress", f"127.0.0.1:{CHROME_DEBUG_PORT}")  # Connect to existing Chrome

    # Blocks until connected to Chrome !
    driver = webdriver.Chrome(
        options=chrome_options
    )
    driver.minimize_window()

def _open_browser():
    try:
        response = requests.get(f"http://localhost:{CHROME_DEBUG_PORT}/json")
    except requests.exceptions.RequestException:
        print('~~WARNING~~ Chrome didn\'t show because it was closed while loading Odoo (limitation of this script)!')
        return
    target_window_handle = None
    for tab in response.json():
        # Some tabs contain script that are working in the background, we need to filter the "real" tabs
        if tab.get('type', '') == 'page':
            if not tab.get('url', '').startswith(ODOO_URL_START):
                continue
            target_window_handle = tab.get('id')
            break

    if target_window_handle:
        driver.switch_to.window(target_window_handle)
        driver.refresh()
    else:
        driver.get(ODOO_URL_START)
    if driver.current_url.startswith(f'{ODOO_URL_START}web/login'):
        if LOGIN == '' or PASSWORD == '':
            raise Exception('Expected a login and a password passed through the arguments!')

        login = driver.find_element(By.ID, "login")
        wait = WebDriverWait(driver, timeout=4)
        wait.until(lambda _ : login.is_displayed())
        # Refresh login: get the displayed element!
        login = driver.find_element(By.ID, "login")
        # Clicking on the window shows it anyway
        driver.maximize_window()
        login.click()
        # The moment the login is clicked, Chrome sometimes fill automatically the fields
        wait.until(lambda _ : login.is_displayed())
        login = driver.find_element(By.ID, "login")
        if login.text != LOGIN:
            login.clear()
            login.send_keys(LOGIN)
        password = driver.find_element(By.ID, "password")
        wait.until(lambda _ : password.is_displayed())
        password = driver.find_element(By.ID, "password")
        password.click()
        password.clear()
        password.send_keys(PASSWORD)
        password.send_keys(Keys.RETURN)
    else:
        driver.maximize_window()

thread = threading.Thread(target=_open_browser)

def web_server_ready_callback():
    if not IS_SHELL and OPEN_CHROME_ON_WEB_SERVER_READY and SHOW_CHROME:
        # webbrowser didn't work
        # os.system('chrome') didn't work
        # subprocess.Popen(['google-chrome', url], ...) didn't work
        # So I used Selenium from a thread
        thread.start()
    elif SHOW_NOTIFICATION_ON_WEB_SERVER_READY:
        subprocess.run('notify-send --transient --icon info --urgency normal "Web Server Ready" "READY"',
            shell=True, executable="/bin/bash", check=True)

def tests_ended_callback(odoo_test_result):
    if not SHOW_NOTIFICATION_ON_TEST_END:
        return
    errors = odoo_test_result.errors_count
    failures = odoo_test_result.failures_count
    testRun = odoo_test_result.testsRun
    test_header = 'PASSED' if errors + failures == 0 else 'FAILED'
    subprocess.run(f'notify-send --transient --icon info --urgency normal "The Tests {test_header}" "{failures} failed, {errors} error(s) of {testRun} tests"',
        shell=True, executable="/bin/bash", check=True)


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
