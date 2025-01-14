###############################################################################
##                                                                           ##
##                     Omnilog logging library                               ##
##                                                                           ##
##   (c) Christoph Herzog <chris@theduke.at> 2015                            ##
##                                                                           ##
##   This project is under the LGPL license.                                 ##
##   Check LICENSE.txt for details.                                          ##
##                                                                           ##
###############################################################################


from strutils import split, contains, startsWith, rfind, format
from sequtils import nil
from times import nil
import tables

from values import Map, newValueMap, `[]=`, `.=`, toValue


###########
# LogDefect. #
###########

type LogDefect* = object of Defect

proc newLogDefect*(msg: string): ref Exception =
  newException(LogDefect, msg)

type
  Severity* {.pure.} = enum
    UNKNOWN
    EMERGENCY
    ALERT
    CRITICAL
    ERROR
    WARNING
    NOTICE
    INFO
    DEBUG
    TRACE
    CUSTOM

  Entry* = object
    logger*: Logger

    facility*: string
    severity*: Severity
    customSeverity*: string
    time*: times.DateTime
    msg*: string
    fields*: Map

  Formatter* = ref object of RootObj
    discard

  Handler* = ref object of RootObj
    minSeverity*: Severity
    filters*: seq[proc(e: Entry): bool]
    formatters*: seq[Formatter]

  Config = ref object of RootObj
    facility: string
    minSeverity: Severity

    rootConfig: RootConfig
    parent: Config

    hasHandlers: bool
    handlers: Table[string, Handler]

    formatters: seq[Formatter]

  RootConfig = ref object of Config
    customSeverities: seq[string]
    configs: Table[string, Config]

  Logger* = ref object of RootObj
    facility: string
    config: Config

##############
# Formatter. #
##############

method format(f: Formatter, e: ref Entry) {.base.} =
  assert false, "Formatter does not implement .format()"

###########
# Handler. #
###########

method close*(w: Handler, force: bool = false, wait: bool = true) {.base.} =
  assert false, "Handler does not implement .close()"

method shouldWrite*(w: Handler, e: Entry): bool {.base.} =
  if e.severity > w.minSeverity:
    return false
  for f in w.filters:
    if not f(e):
      return false 
  return true

method doWrite*(w: Handler, e: Entry) {.base.} =
  assert false, "Handler does not implement .doWrite()"

method write*(w: Handler, e: Entry) {.base.} =
  if not w.shouldWrite(e):
    return
  var eRef: ref Entry
  new(eRef)
  eRef[] = e
  for f in w.formatters:
    f.format(eRef)
  w.doWrite(eRef[])

proc addFilter*(w: Handler, filter: proc(e: Entry): bool) =
  w.filters.add(filter)

proc clearFilters*(w: Handler) =
  w.filters = @[]

proc addFormatter*(w: Handler, formatter: Formatter) =
  w.formatters.add(formatter)

proc clearFormatters*(w: Handler) =
  w.formatters = @[]

###############################
# Formatter / Handler imports. #
###############################

import omnilog/formatters/message
import omnilog/handlers/file



###########
# Config. #
###########

proc newRootConfig(): RootConfig =
  result = RootConfig(
    facility: "",
    minSeverity: Severity.CUSTOM,
    hasHandlers: true,
    handlers: initTable[string, Handler](),
    formatters: @[],
    customSeverities: @[],
    configs: initTable[string, Config]()
  )
  result.rootConfig = result

proc buildChild(c: Config, facility: string): Config =
  var facility = facility
  if not facility.startsWith(c.facility):
    facility = c.facility & "." & facility

  Config(
    facility: facility,
    minSeverity: c.minSeverity,
    rootConfig: c.rootConfig,
    parent: c,
  )

proc getHandlers(c: Config): seq[Handler] =
  if c.hasHandlers:
    result = sequtils.toSeq(c.handlers.values)
  else:
    result = c.parent.getHandlers()

proc getFormatters(c: Config): seq[Formatter] =
  if c.formatters.len > 0:
    c.formatters
  elif c.parent != nil:
    c.parent.getFormatters()
  else:
    @[]

proc getCustomSeverities(c: Config): seq[string] =
  c.rootConfig.customSeverities



###########
# Logger. #
###########

proc getLogger*(l: Logger, facility: string): Logger =
  var facility = facility
  if not facility.startsWith(l.facility):
    facility = l.facility & "." & facility

  var rootConfig = l.config.rootConfig
  # Find the closest parent config.
  var configFacility = facility
  while configFacility.contains(".") and not rootConfig.configs.hasKey(configFacility):
    configFacility = configFacility[0..rfind(configFacility, ".") - 1]

  var config: Config = rootConfig
  if rootConfig.configs.hasKey(configFacility):
    config = rootConfig.configs[configFacility]

  Logger(facility: facility, `config`: config)

proc setFacility*(l: Logger, facility: string) =
  l.facility = facility

proc setSeverity*(l: Logger, s: Severity) =
  if l.config.facility != l.facility:
    l.config = l.config.buildChild(l.facility)
  l.config.minSeverity = s

proc addHandler*(l: Logger, name: string, w: Handler) =
  if l.config.facility != l.facility:
    l.config = l.config.buildChild(l.facility)
  if not l.config.hasHandlers:
    l.config.handlers = l.config.parent.handlers
    l.config.hasHandlers = true
  l.config.handlers[name] = w

proc clearHandlers*(l: Logger) =
  if l.config.facility != l.facility:
    l.config = l.config.buildChild(l.facility)
    l.config.hasHandlers = true
  l.config.handlers = initTable[string, Handler]()

proc getHandler*(l: Logger, name: string): Handler =
  var conf = l.config
  while not conf.hasHandlers:
    conf = conf.parent
  if not conf.handlers.hasKey(name):
    raise newLogDefect("Unknown handler: '" & name & "'")
  conf.handlers[name]

proc getHandlers*(l: Logger): seq[Handler] =
  var conf = l.config
  while not conf.hasHandlers:
    conf = conf.parent
  return sequtils.toSeq(conf.handlers.values)

proc addFormatter*(l: Logger, f: Formatter) =
  if l.config.facility != l.facility:
    l.config = l.config.buildChild(l.facility)
    l.config.formatters = l.config.parent.formatters
  l.config.formatters.add(f)

proc clearFormatters*(l: Logger) =
  if l.config.facility != l.facility:
    l.config = l.config.buildChild(l.facility)
  l.config.formatters = @[]

proc setFormatter*(l: Logger, f: Formatter) =
  l.clearFormatters()
  l.config.formatters.add(f)

proc setFormatters*(l: Logger, f: seq[Formatter]) =
  l.clearFormatters()
  l.config.formatters = f

proc getFormatters*(l: Logger): seq[Formatter] =
  l.config.getFormatters()

proc registerSeverity*(l: Logger, severity: string) =
  l.config.rootConfig.customSeverities.add(severity)

proc newRootLogger*(withDefaultHandler: bool = true): Logger =
  result = Logger(
    facility: "",
    config: newRootConfig()
  )

  if withDefaultHandler:
    result.addHandler("stdout", newFileHandler(file=stdout)) 

###############
# newEntry(). #
###############

proc newEntry*(facility: string, severity: Severity, msg: string, customSeverity: string = "", fields: Map = nil): Entry =
  Entry(
    facility: facility,
    severity: severity,
    msg: msg,
    time: times.now(),
    fields: fields
  )

#########################
# Logger logging procs. #
#########################

proc log*(l: Logger, e: Entry) =
  # Log arbitrary entries.

  if e.severity == Severity.UNKNOWN:
    raise newLogDefect("Can't log entries with severity: UNKNOWN")

  if e.severity > l.config.minSeverity:
    # Ignore severities which should not be logged.
    return

  let eRef = new(Entry)
  eRef[] = e

  eRef[].facility = l.facility

  if e.msg == "":
    eRef[].msg = ""

  for f in l.config.getFormatters:
    f.format(eRef)
  for w in l.config.getHandlers:
    w.write(eRef[])

# General severity log.

proc log*(l: Logger, severity: Severity, msg: string, args: varargs[string, `$`]) =
  var msg = if msg == nil: "" else: msg
  # Log a message with specified severity.
  l.log(newEntry(l.facility, severity, msg.format(args)))

# General custom Severity log.

proc log*(l: Logger, customSeverity: string, msg: string, args: varargs[string, `$`]) =
  # Log a message with a custom severity.
  var msg = if msg == nil: "" else: msg
  if not (l.config.getCustomSeverities().contains(customSeverity)):
    raise newLogDefect("Unregistered custom severity: " & customSeverity)
  l.log(newEntry(l.facility, Severity.CUSTOM, msg.format(args), customSeverity = customSeverity))

# Emergency.

proc emergency*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.EMERGENCY, msg, args)

# Alert.

proc alert*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.ALERT, msg, args)

# Critical.

proc critical*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.CRITICAL, msg, args)

# Error.

proc error*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.ERROR, msg, args)

# Warning.

proc warning*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.WARNING, msg, args)

# Notice.

proc notice*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.NOTICE, msg, args)

# Info.

proc info*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.INFO, msg, args)

# Debug.

proc debug*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.DEBUG, msg, args)

proc trace*(l: Logger, msg: string, args: varargs[string, `$`]) =
  l.log(Severity.TRACE, msg, args)

######################
# Entry field logic. #
######################

proc withField*[T](l: Logger, name: string, value: T): Entry =
  var m = newValueMap()
  m[name] = value
  result = newEntry(nil, Severity.UNKNOWN, nil, nil, m)
  result.logger = l

proc withFields*(l: Logger, fields: tuple): Entry =
  result = newEntry(nil, Severity.UNKNOWN, nil, nil, toValue(fields))
  result.logger = l

proc addField*[T](e: Entry, name: string, value: T): Entry =
  if e.fields == nil:
    e.fields = newValueMap()
  e.fields[name] = value
  return e

proc addFields*(e: Entry, t: tuple): Entry =
  if e.fields == nil:
    e.fields = newValueMap()
  for key, val in t.fieldPairs:
    e.fields[key] = val
  return e

proc log*(e: Entry, severity: Severity, msg: string, args: varargs[string, `$`]) =
  # Log a message with specified severity.

  var msg = if msg == nil: "" else: msg
  var e = e
  e.severity = severity
  e.msg = msg.format(args)
  e.logger.log(e)

# General custom Severity log.

proc log*(e: Entry, customSeverity: string, msg: string, args: varargs[string, `$`]) =
  # Log a message with a custom severity.

  if not (e.logger.config.getCustomSeverities().contains(customSeverity)):
    raise newLogDefect("Unregistered custom severity: " & customSeverity)
  var msg = if msg == nil: "" else: msg
  var e = e
  e.severity = Severity.CUSTOM
  e.customSeverity = customSeverity
  e.msg = msg.format(args)
  e.logger.log(e)

# Emergency.

proc emergency*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.EMERGENCY, msg, args)

# Alert.

proc alert*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.ALERT, msg, args)

# Critical.

proc critical*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.CRITICAL, msg, args)

# Error.

proc error*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.ERROR, msg, args)

# Warning.

proc warning*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.WARNING, msg, args)

# Notice.

proc notice*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.NOTICE, msg, args)

# Info.

proc info*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.INFO, msg, args)

# Debug.

proc debug*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.DEBUG, msg, args)

# Trace.

proc trace*(e: Entry, msg: string, args: varargs[string, `$`]) =
  e.log(Severity.TRACE, msg, args)

##################
# Global logger. #
##################

var globalLogger = newRootLogger()

proc setFormat*(format: string) =
  for w in globalLogger.config.getHandlers():
    for f in w.formatters:
      if f is MessageFormatter:
        cast[MessageFormatter](f).setFormat(format)

proc getLogger*(facility: string): Logger =
  globalLogger.getLogger(facility)

proc setFormat*(format: Format) =
  setFormat($format)

proc withField*[T](name: string, val: T): Entry =
  globalLogger.withField(name, val)

proc logFields*(fields: tuple): Entry =
  globalLogger.withFields(fields)

proc log*(severity: Severity, msg: string, args: varargs[string, `$`]) =
  globalLogger.log(severity, msg, args)

# General custom Severity log.

proc log*(customSeverity: string, msg: string, args: varargs[string, `$`]) =
  globalLogger.log(customSeverity, msg, args)

# Emergency.

proc emergency*(msg: string, args: varargs[string, `$`]) =
  globalLogger.emergency(msg, args)

# Alert.

proc alert*(msg: string, args: varargs[string, `$`]) =
  globalLogger.alert(msg, args)

# Critical.

proc critical*(msg: string, args: varargs[string, `$`]) =
  globalLogger.critical(msg, args)

# Error.

proc error*(msg: string, args: varargs[string, `$`]) =
  globalLogger.error(msg, args)

# Warning.

proc warning*(msg: string, args: varargs[string, `$`]) =
  globalLogger.warning(msg, args)

# Notice.

proc notice*(msg: string, args: varargs[string, `$`]) =
  globalLogger.notice(msg, args)

# Info.

proc info*(msg: string, args: varargs[string, `$`]) =
  globalLogger.info(msg, args)

# Debug.

proc debug*(msg: string, args: varargs[string, `$`]) =
  globalLogger.debug(msg, args)

# Trace.

proc trace*(msg: string, args: varargs[string, `$`]) =
  globalLogger.trace(msg, args)
