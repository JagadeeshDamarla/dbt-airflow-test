{{ config(materialized='view') }}

{% set from_date = var('from_date') %}
{% set to_date = var('to_date') %}

-- cte in view.     
with customer_info as ( 

    select *
    from {{ ref('customer_seed_view') }}

)

select *
from customer_info
where 1=1
    and cast(signup_date as date) >= cast('{{ from_date }}' as date)
    and cast(signup_date as date) <= cast('{{ to_date }}' as date)