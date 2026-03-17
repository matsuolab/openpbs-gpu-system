import pbs
pbs.logmsg(pbs.LOG_WARNING, "TEST_HOOK: event type=%s" % str(pbs.event().type))
pbs.event().accept()
