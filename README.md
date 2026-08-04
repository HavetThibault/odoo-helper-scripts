# odoo-helper-scripts
## Nicer Logs Please
Instead of running `odoo-bin`, run `scripts/released/nicer_logs_please.py` (you can get some inspiration on the `o` script that does that) which will overwrite some part of the python built-in `logging` library, and then launch Odoo (the end of the file is the same as `odoo-bin`).

When running this file (and so, Odoo):
- If `--log-level` is specified, it will display all the logs which level is higher or equal to the specified minimum log level, plus logs specified in a variable of the script (see below)
- If `--log-level` is not specified, it will keep pooping all the logs

This script will also:
- Show a progress bar while loading the module
- Run some code when the tests are done or when the web server is ready (by default, it throws a notification)

### CONFIG
The config of this script is managed through some variables in the script file itself (you'll easily find them):
- If you want it to display more logs/hide logs, feel free to modify `DISPLAYED_RECORD_NAMES` and/or `DISPLAYED_RECORD_NAMES_COND`.
- Setting `SHOW_ALL_LOGS_AGAIN` will disable/enable this "logging extension"
- ...

**WARNING**: this patch may break depending on the logging library version (standard python library only tested in 3.12)


### Advanced notes
For each newly created logger:
    If the logger level (the level threshold below which logs aren't displayed) is higher than `logging.INFO`, then the level of the logger is set back to the `logging.INFO`
    Then we attach a `PleaseFilterImportantLogsDearGodooFilter` to this logger, and this filter will only keep the logs with a higher or equal level to the original logger level (stored in `min_log_level`), OR the "important logs"

If the filter `min_log_level` is 0, this filter will iterate through the loggers hierarchy until it finds a logger with a non zero `min_log_level` filter and use this threshold instead (see `PleaseFilterImportantLogsDearGodooFilter.filter`).

The progress bar is displayed by overwriting the `logging.Formatter.format` method.
The end of tests/server ready callables (notification) are managed in the `PleaseFilterImportantLogsDearGodooFilter`.


## o
This script offers some nice tools to launch/test Odoo.

His guide and an option --help will come in a future commit.