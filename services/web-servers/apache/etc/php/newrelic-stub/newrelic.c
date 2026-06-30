#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "php.h"
#include "ext/standard/info.h"
#include "php_ini.h"

#define PHP_NEWRELIC_EXTNAME "newrelic"
#define PHP_NEWRELIC_VERSION "1.0.0-mock"

/* ── INI entries ─────────────────────────────────────────────────────────── */
/* NULL handler: values live in the ini system, readable/writable via        */
/* ini_get() / ini_set() from PHP without needing C-side struct members.     */

PHP_INI_BEGIN()
    PHP_INI_ENTRY("newrelic.enabled",                            "1",  PHP_INI_ALL, NULL)
    PHP_INI_ENTRY("newrelic.appname",                "PHP Application",  PHP_INI_ALL, NULL)
    PHP_INI_ENTRY("newrelic.license",                            "",   PHP_INI_ALL, NULL)
    PHP_INI_ENTRY("newrelic.capture_params",                     "0",  PHP_INI_ALL, NULL)
    PHP_INI_ENTRY("newrelic.distributed_tracing_enabled",        "0",  PHP_INI_ALL, NULL)
    PHP_INI_ENTRY("newrelic.browser_monitoring.auto_instrument", "1",  PHP_INI_ALL, NULL)
    PHP_INI_ENTRY("newrelic.transaction_tracer.enabled",         "1",  PHP_INI_ALL, NULL)
    PHP_INI_ENTRY("newrelic.transaction_tracer.detail",          "1",  PHP_INI_ALL, NULL)
    PHP_INI_ENTRY("newrelic.error_collector.enabled",            "1",  PHP_INI_ALL, NULL)
PHP_INI_END()

/* ── Module globals (per-request handler registry) ───────────────────────── */

ZEND_BEGIN_MODULE_GLOBALS(newrelic)
    HashTable handlers;
ZEND_END_MODULE_GLOBALS(newrelic)

ZEND_DECLARE_MODULE_GLOBALS(newrelic)

#ifdef ZTS
# define NR_G(v) TSRMG(newrelic_globals_id, zend_newrelic_globals *, v)
#else
# define NR_G(v) (newrelic_globals.v)
#endif

/* ── NewRelicMockPayload class (returned by newrelic_create_distributed_trace_payload) ── */

static zend_class_entry *newrelic_mock_payload_ce;

PHP_METHOD(NewRelicMockPayload, httpSafe) { ZEND_PARSE_PARAMETERS_NONE(); RETURN_EMPTY_STRING(); }
PHP_METHOD(NewRelicMockPayload, text)     { ZEND_PARSE_PARAMETERS_NONE(); RETURN_EMPTY_STRING(); }
PHP_METHOD(NewRelicMockPayload, isEmpty)  { ZEND_PARSE_PARAMETERS_NONE(); RETURN_TRUE; }

ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_payload_str,  0, 0, IS_STRING, 0) ZEND_END_ARG_INFO()
ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_payload_bool, 0, 0, _IS_BOOL,  0) ZEND_END_ARG_INFO()

static const zend_function_entry newrelic_mock_payload_methods[] = {
    PHP_ME(NewRelicMockPayload, httpSafe, arginfo_payload_str,  ZEND_ACC_PUBLIC)
    PHP_ME(NewRelicMockPayload, text,     arginfo_payload_str,  ZEND_ACC_PUBLIC)
    PHP_ME(NewRelicMockPayload, isEmpty,  arginfo_payload_bool, ZEND_ACC_PUBLIC)
    PHP_FE_END
};

/* ── Dispatch helper ─────────────────────────────────────────────────────── */
/*
 * Looks up a PHP callable registered via newrelic_mock_set().
 * If found, calls it forwarding all arguments from the current stack frame
 * and writes the result into *rv.  Returns 1 if a handler was called, 0 otherwise.
 */
static int nr_dispatch(const char *name, zend_execute_data *ex, zval *rv)
{
    zval *cb = zend_hash_str_find(&NR_G(handlers), name, strlen(name));
    if (!cb) return 0;

    uint32_t argc = ZEND_CALL_NUM_ARGS(ex);
    zval *args = argc ? safe_emalloc(argc, sizeof(zval), 0) : NULL;
    for (uint32_t i = 0; i < argc; i++) {
        ZVAL_COPY(&args[i], ZEND_CALL_ARG(ex, i + 1));
    }

    call_user_function(NULL, NULL, cb, rv, argc, args);

    for (uint32_t i = 0; i < argc; i++) zval_ptr_dtor(&args[i]);
    if (args) efree(args);
    return 1;
}

/* ── Handler management ──────────────────────────────────────────────────── */
/*
 * newrelic_mock_set(string $function, callable $handler): void
 *   Register a PHP callable that overrides the named stub for this request.
 *   The callable receives the same arguments as the real NR function.
 *
 * newrelic_mock_reset(?string $function = null): void
 *   Remove a single handler, or all handlers when called without arguments.
 */

ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_mock_set, 0, 2, IS_VOID, 0)
    ZEND_ARG_TYPE_INFO(0, function, IS_STRING, 0)
    ZEND_ARG_INFO(0, handler)
ZEND_END_ARG_INFO()

ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_mock_reset, 0, 0, IS_VOID, 0)
    ZEND_ARG_TYPE_INFO(0, function, IS_STRING, 1)
ZEND_END_ARG_INFO()

PHP_FUNCTION(newrelic_mock_set)
{
    zend_string *name;
    zval *cb;
    ZEND_PARSE_PARAMETERS_START(2, 2)
        Z_PARAM_STR(name)
        Z_PARAM_ZVAL(cb)
    ZEND_PARSE_PARAMETERS_END();

    Z_TRY_ADDREF_P(cb);
    zend_hash_update(&NR_G(handlers), name, cb);
}

PHP_FUNCTION(newrelic_mock_reset)
{
    zend_string *name = NULL;
    ZEND_PARSE_PARAMETERS_START(0, 1)
        Z_PARAM_OPTIONAL
        Z_PARAM_STR_OR_NULL(name)
    ZEND_PARSE_PARAMETERS_END();

    if (name) {
        zend_hash_del(&NR_G(handlers), name);
    } else {
        zend_hash_clean(&NR_G(handlers));
    }
}

/* ── Stub macros ─────────────────────────────────────────────────────────── */

/* Catch-all arginfo: accepts any arguments, no strict type checking */
ZEND_BEGIN_ARG_INFO_EX(arginfo_nr_stub, 0, 0, 0)
    ZEND_ARG_VARIADIC_INFO(0, args)
ZEND_END_ARG_INFO()

/* bool-returning stubs (default true / false) */
#define NR_STUB_TRUE(fn) \
    PHP_FUNCTION(fn) { if (!nr_dispatch(#fn, execute_data, return_value)) RETURN_TRUE; }

#define NR_STUB_FALSE(fn) \
    PHP_FUNCTION(fn) { if (!nr_dispatch(#fn, execute_data, return_value)) RETURN_FALSE; }

/* void stubs: call handler if set, otherwise no-op */
#define NR_STUB_VOID(fn) \
    PHP_FUNCTION(fn) { \
        zval _rv; ZVAL_NULL(&_rv); \
        nr_dispatch(#fn, execute_data, &_rv); \
        zval_ptr_dtor(&_rv); \
    }

/* ── Application / transaction ───────────────────────────────────────────── */

NR_STUB_TRUE(newrelic_set_appname)
NR_STUB_TRUE(newrelic_start_transaction)
NR_STUB_TRUE(newrelic_end_transaction)
NR_STUB_VOID(newrelic_end_of_transaction)
NR_STUB_VOID(newrelic_ignore_transaction)
NR_STUB_VOID(newrelic_ignore_apdex)
NR_STUB_VOID(newrelic_background_job)
NR_STUB_TRUE(newrelic_name_transaction)
NR_STUB_VOID(newrelic_capture_params)

/* ── Error handling ──────────────────────────────────────────────────────── */

NR_STUB_VOID(newrelic_notice_error)

/* ── Custom attributes ───────────────────────────────────────────────────── */

NR_STUB_TRUE(newrelic_add_custom_parameter)
NR_STUB_TRUE(newrelic_add_custom_span_parameter)
NR_STUB_TRUE(newrelic_set_user_attributes)

/* ── Custom events / metrics / tracers ───────────────────────────────────── */

NR_STUB_VOID(newrelic_record_custom_event)
NR_STUB_TRUE(newrelic_add_custom_tracer)
NR_STUB_TRUE(newrelic_timing)

PHP_FUNCTION(newrelic_record_datastore_segment)
{
    if (!nr_dispatch("newrelic_record_datastore_segment", execute_data, return_value)) {
        zval *func, *params;
        ZEND_PARSE_PARAMETERS_START(2, 2)
            Z_PARAM_ZVAL(func)
            Z_PARAM_ARRAY(params)
        ZEND_PARSE_PARAMETERS_END();
        call_user_function(NULL, NULL, func, return_value, 0, NULL);
    }
}

/* ── Browser monitoring ──────────────────────────────────────────────────── */

NR_STUB_TRUE(newrelic_disable_autorum)

PHP_FUNCTION(newrelic_get_browser_timing_header)
{
    if (!nr_dispatch("newrelic_get_browser_timing_header", execute_data, return_value)) {
        bool include_tags = 1;
        ZEND_PARSE_PARAMETERS_START(0, 1)
            Z_PARAM_OPTIONAL
            Z_PARAM_BOOL(include_tags)
        ZEND_PARSE_PARAMETERS_END();

        const char *js =
            "window.NREUM=window.NREUM||{};"
            "NREUM.info={\"mock\":true,\"agent\":\"\",\"beacon\":\"\","
            "\"errorBeacon\":\"\",\"licenseKey\":\"\",\"applicationID\":\"\","
            "\"transactionName\":\"\",\"queueTime\":0,\"applicationTime\":0};";

        if (include_tags) {
            char *result;
            size_t len = spprintf(&result, 0,
                "<script type=\"text/javascript\">%s</script>", js);
            RETVAL_STRINGL(result, len);
            efree(result);
        } else {
            RETURN_STRING(js);
        }
    }
}

PHP_FUNCTION(newrelic_get_browser_timing_footer)
{
    if (!nr_dispatch("newrelic_get_browser_timing_footer", execute_data, return_value)) {
        bool include_tags = 1;
        ZEND_PARSE_PARAMETERS_START(0, 1)
            Z_PARAM_OPTIONAL
            Z_PARAM_BOOL(include_tags)
        ZEND_PARSE_PARAMETERS_END();
        RETURN_STRING(include_tags ? "<!-- NREUM mock footer -->" : "");
    }
}

/* ── Distributed tracing ─────────────────────────────────────────────────── */

NR_STUB_TRUE(newrelic_insert_distributed_trace_headers)
NR_STUB_TRUE(newrelic_accept_distributed_trace_headers)
NR_STUB_FALSE(newrelic_is_sampled)
NR_STUB_TRUE(newrelic_accept_distributed_trace_payload)

PHP_FUNCTION(newrelic_create_distributed_trace_payload)
{
    if (!nr_dispatch("newrelic_create_distributed_trace_payload", execute_data, return_value)) {
        object_init_ex(return_value, newrelic_mock_payload_ce);
    }
}

/* ── Function table ──────────────────────────────────────────────────────── */

static const zend_function_entry newrelic_functions[] = {
    PHP_FE(newrelic_mock_set,   arginfo_mock_set)
    PHP_FE(newrelic_mock_reset, arginfo_mock_reset)

    PHP_FE(newrelic_set_appname,                        arginfo_nr_stub)
    PHP_FE(newrelic_start_transaction,                  arginfo_nr_stub)
    PHP_FE(newrelic_end_transaction,                    arginfo_nr_stub)
    PHP_FE(newrelic_end_of_transaction,                 arginfo_nr_stub)
    PHP_FE(newrelic_ignore_transaction,                 arginfo_nr_stub)
    PHP_FE(newrelic_ignore_apdex,                       arginfo_nr_stub)
    PHP_FE(newrelic_background_job,                     arginfo_nr_stub)
    PHP_FE(newrelic_name_transaction,                   arginfo_nr_stub)
    PHP_FE(newrelic_capture_params,                     arginfo_nr_stub)
    PHP_FE(newrelic_notice_error,                       arginfo_nr_stub)
    PHP_FE(newrelic_add_custom_parameter,               arginfo_nr_stub)
    PHP_FE(newrelic_add_custom_span_parameter,          arginfo_nr_stub)
    PHP_FE(newrelic_set_user_attributes,                arginfo_nr_stub)
    PHP_FE(newrelic_record_custom_event,                arginfo_nr_stub)
    PHP_FE(newrelic_record_datastore_segment,           arginfo_nr_stub)
    PHP_FE(newrelic_add_custom_tracer,                  arginfo_nr_stub)
    PHP_FE(newrelic_timing,                             arginfo_nr_stub)
    PHP_FE(newrelic_disable_autorum,                    arginfo_nr_stub)
    PHP_FE(newrelic_get_browser_timing_header,          arginfo_nr_stub)
    PHP_FE(newrelic_get_browser_timing_footer,          arginfo_nr_stub)
    PHP_FE(newrelic_insert_distributed_trace_headers,   arginfo_nr_stub)
    PHP_FE(newrelic_accept_distributed_trace_headers,   arginfo_nr_stub)
    PHP_FE(newrelic_is_sampled,                         arginfo_nr_stub)
    PHP_FE(newrelic_create_distributed_trace_payload,   arginfo_nr_stub)
    PHP_FE(newrelic_accept_distributed_trace_payload,   arginfo_nr_stub)

    PHP_FE_END
};

/* ── Lifecycle ───────────────────────────────────────────────────────────── */

PHP_MINIT_FUNCTION(newrelic)
{
    REGISTER_INI_ENTRIES();

    zend_class_entry ce;
    INIT_CLASS_ENTRY(ce, "NewRelicMockPayload", newrelic_mock_payload_methods);
    newrelic_mock_payload_ce = zend_register_internal_class(&ce);
    return SUCCESS;
}

PHP_MSHUTDOWN_FUNCTION(newrelic)
{
    UNREGISTER_INI_ENTRIES();
    return SUCCESS;
}

PHP_RINIT_FUNCTION(newrelic)
{
    zend_hash_init(&NR_G(handlers), 8, NULL, ZVAL_PTR_DTOR, 0);
    return SUCCESS;
}

PHP_RSHUTDOWN_FUNCTION(newrelic)
{
    zend_hash_destroy(&NR_G(handlers));
    return SUCCESS;
}

PHP_MINFO_FUNCTION(newrelic)
{
    php_info_print_table_start();
    php_info_print_table_row(2, "newrelic", "mock");
    php_info_print_table_row(2, "version", PHP_NEWRELIC_VERSION);
    php_info_print_table_end();
}

/* ── Module entry ────────────────────────────────────────────────────────── */

zend_module_entry newrelic_module_entry = {
    STANDARD_MODULE_HEADER,
    PHP_NEWRELIC_EXTNAME,
    newrelic_functions,
    PHP_MINIT(newrelic),
    PHP_MSHUTDOWN(newrelic),
    PHP_RINIT(newrelic),
    PHP_RSHUTDOWN(newrelic),
    PHP_MINFO(newrelic),
    PHP_NEWRELIC_VERSION,
    PHP_MODULE_GLOBALS(newrelic),
    NULL,  /* globals_ctor */
    NULL,  /* globals_dtor */
    NULL,  /* post_deactivate_func */
    STANDARD_MODULE_PROPERTIES_EX
};

#ifdef COMPILE_DL_NEWRELIC
ZEND_GET_MODULE(newrelic)
#endif
