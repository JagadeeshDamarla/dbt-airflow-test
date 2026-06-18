{{ config(materialized='view') }}

-- cte in
with customer_seed as (

    select *
    from {{ ref('customer_seed') }}

)

select
    customer_id,
    first_name,
    last_name,
    first_name || ' ' || last_name as full_name,
    city,
    state,
    city || ', ' || state as city_state,
    signup_date,
    extract(year from cast(signup_date as date)) as signup_year,
    account_tier,
    lifetime_value,
    case
        when lifetime_value >= 1500 then 'high'
        when lifetime_value >= 700 then 'medium'
        else 'low'
    end as value_segment,
    case
        when account_tier = 'gold' then true
        else false
    end as is_gold_customer
from customer_seed