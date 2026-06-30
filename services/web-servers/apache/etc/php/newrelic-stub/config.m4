PHP_ARG_ENABLE([newrelic],
  [whether to enable newrelic mock],
  [AS_HELP_STRING([--enable-newrelic], [Enable newrelic mock extension])],
  [yes])

if test "$PHP_NEWRELIC" != "no"; then
  PHP_NEW_EXTENSION(newrelic, newrelic.c, $ext_shared,, -DZEND_ENABLE_STATIC_TSRMLS_CACHE=1)
fi
