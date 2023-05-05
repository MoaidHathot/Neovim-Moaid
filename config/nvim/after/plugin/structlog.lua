local log = require('structlog')

log.configure({
  moaid_vim = {
    pipelines = {
      {
        level = log.level.INFO,
        processors = {
          log.processors.StackWriter({ "line", "file" }, { max_parents = 0, stack_level = 0 }),
          log.processors.Timestamper("%H:%M:%S"),
        },
        formatter = log.formatters.FormatColorizer( --
          "%s [%s] %s: %-30s",
          { "timestamp", "level", "logger_name", "msg" },
          { level = log.formatters.FormatColorizer.color_level() }
        ),
        sink = log.sinks.Console(),
      },
      {
        level = log.level.WARN,
        processors = {},
        formatter = log.formatters.Format( --
          "%s",
          { "msg" },
          { blacklist = { "level", "moaid" } }
        ),
        sink =  log.sinks.NvimNotify(),
      },
      {
        level = log.level.TRACE,
        processors = {
          log.processors.StackWriter({ "line", "file" }, { max_parents = 3 }),
          log.processors.Timestamper("%H:%M:%S"),
        },
        formatter = log.formatters.Format( --
          "%s [%s] %s: %-30s",
          { "timestamp", "level", "logger_name", "msg" }
        ),
        sink = log.sinks.File("./test.log"),
      },
    },
  },
  -- other_logger = {...}
})

