{% macro _escape_sql_string(val) -%}
  {{ return((val | string) | replace("'", "''")) }}
{%- endmacro %}

{% macro log_run_results(results) %}
  {#
    Persist dbt invocation and per-node execution metadata after each run.
    This macro is intended for Snowflake targets.
  #}
  {% if not execute %}
    {{ return('') }}
  {% endif %}

  {% if target.type != 'snowflake' %}
    {% do log('on-run-end logging skipped because target is not Snowflake.', info=True) %}
    {{ return('') }}
  {% endif %}

  {% set audit_database = target.database %}
  {% set audit_schema = target.schema %}
  {% set audit_table = 'DBT_RUN_AUDIT' %}
  {% set relation_name = audit_database ~ '.' ~ audit_schema ~ '.' ~ audit_table %}

  {% set create_table_sql %}
    create table if not exists {{ relation_name }} (
      invocation_id string,
      generated_at timestamp_tz,
      run_started_at timestamp_tz,
      run_completed_at timestamp_tz,
      target_name string,
      target_database string,
      target_schema string,
      node_unique_id string,
      model_name string,
      resource_type string,
      status string,
      execution_time_seconds float,
      message string,
      adapter_response variant
    )
  {% endset %}

  {% do run_query(create_table_sql) %}

  {% set run_completed_at = modules.datetime.datetime.utcnow().isoformat() %}

  {% if results is not iterable or (results | length) == 0 %}
    {% do log('on-run-end logging: no node-level results available for this invocation.', info=True) %}
    {{ return('') }}
  {% endif %}

  {% for result in results %}
    {% set node = result.node %}
    {% set node_unique_id = _escape_sql_string(node.unique_id) %}
    {% set model_name = _escape_sql_string(node.name) %}
    {% set resource_type = _escape_sql_string(node.resource_type) %}
    {% set status = _escape_sql_string(result.status) %}
    {% set message = _escape_sql_string(result.message if result.message is not none else '') %}
    {% set adapter_response = (result.adapter_response if result.adapter_response is not none else {}) | tojson %}

    {% set insert_sql %}
      insert into {{ relation_name }} (
        invocation_id,
        generated_at,
        run_started_at,
        run_completed_at,
        target_name,
        target_database,
        target_schema,
        node_unique_id,
        model_name,
        resource_type,
        status,
        execution_time_seconds,
        message,
        adapter_response
      )
      select
        '{{ _escape_sql_string(invocation_id) }}',
        to_timestamp_tz('{{ _escape_sql_string(run_completed_at) }}'),
        to_timestamp_tz('{{ _escape_sql_string(run_started_at.isoformat()) }}'),
        to_timestamp_tz('{{ _escape_sql_string(run_completed_at) }}'),
        '{{ _escape_sql_string(target.name) }}',
        '{{ _escape_sql_string(target.database) }}',
        '{{ _escape_sql_string(target.schema) }}',
        '{{ node_unique_id }}',
        '{{ model_name }}',
        '{{ resource_type }}',
        '{{ status }}',
        {{ result.execution_time if result.execution_time is not none else 'null' }},
        '{{ message }}',
        parse_json('{{ _escape_sql_string(adapter_response) }}')
    {% endset %}

    {% do run_query(insert_sql) %}

    {% do log(
      'on-run-end logging: model=' ~ node.name ~
      ', status=' ~ result.status ~
      ', execution_time=' ~ (result.execution_time | string) ~ 's',
      info=True
    ) %}
  {% endfor %}
{% endmacro %}
