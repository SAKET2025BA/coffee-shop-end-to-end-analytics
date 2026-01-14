/* =====================================================
Coffee Shop Analytics – SQL Data Model
Fact table: coffee.v_sales_typed (from sales_enriched.csv)

1. Schema Setup
2. Raw Data Landing
3. Data Quality Validation
4. Typed Fact View
5. Grain Verification
6. Core Business KPIs
===================================================== */


/* =====================================================
1. SCHEMA SETUP
===================================================== */

CREATE SCHEMA IF NOT EXISTS coffee;

SET search_path TO coffee;


/* =====================================================
2. RAW DATA LANDING (CSV → all TEXT)
   NOTE: Import sales_enriched.csv into this table via pgAdmin Import/Export
===================================================== */

DROP VIEW IF EXISTS coffee.v_sales_typed CASCADE;

DROP TABLE IF EXISTS coffee.sales_enriched_raw CASCADE;

CREATE TABLE coffee.sales_enriched_raw (
  row_id        text,
  order_id      text,
  created_at    text,
  order_date    text,
  order_hour    text,
  shift_bucket  text,
  day_of_week   text,
  cust_name     text,
  in_or_out     text,
  item_id       text,
  sku           text,
  item_name     text,
  item_cat      text,
  item_size     text,
  quantity      text,
  item_price    text,
  revenue       text,
  unit_cost     text,
  total_cost    text,
  contribution  text,
  margin_pct    text
);


/* =====================================================
3. DATA QUALITY VALIDATION (RAW)
===================================================== */

SELECT COUNT(*) AS rows_loaded
FROM coffee.sales_enriched_raw;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'coffee'
  AND table_name = 'sales_enriched_raw'
ORDER BY ordinal_position;

SELECT *
FROM coffee.sales_enriched_raw
LIMIT 10;

SELECT
  COUNT(*) AS rows,
  COUNT(DISTINCT row_id) AS distinct_row_id,
  COUNT(DISTINCT order_id) AS distinct_orders
FROM coffee.sales_enriched_raw;


/* =====================================================
3B. CLEANUP: REMOVE CSV HEADER ROW IF IT GOT IMPORTED AS DATA
===================================================== */

SELECT *
FROM coffee.sales_enriched_raw
WHERE quantity = 'quantity'
   OR item_price = 'item_price'
   OR revenue = 'revenue';
DELETE
FROM coffee.sales_enriched_raw
WHERE quantity = 'quantity'
   OR item_price = 'item_price'
   OR revenue = 'revenue';


/* =====================================================
4. TYPED FACT VIEW (RAW → CLEAN TYPES)
   This is our ANALYTICS fact table.
===================================================== */

CREATE OR REPLACE VIEW coffee.v_sales_typed AS
SELECT
  row_id,
  order_id,
  to_date(order_date, 'DD-MM-YYYY') AS order_date,
  order_hour::integer AS order_hour,
  shift_bucket,
  day_of_week,
  cust_name,
  in_or_out,
  item_id,
  sku,
  item_name,
  item_cat,
  item_size,
  quantity::numeric AS quantity,
  item_price::numeric AS item_price,
  revenue::numeric AS revenue,
  unit_cost::numeric AS unit_cost,
  total_cost::numeric AS total_cost,
  contribution::numeric AS contribution,
  (NULLIF(REPLACE(margin_pct, '%', ''), '')::numeric / 100.0) AS margin_pct
FROM coffee.sales_enriched_raw;

SELECT
  COUNT(*)                      AS line_rows,
  COUNT(DISTINCT row_id)        AS distinct_row_id,
  COUNT(DISTINCT order_id)      AS orders,
  SUM(quantity)                 AS items_sold
FROM coffee.v_sales_typed;


/* =====================================================
5. GRAIN VERIFICATION
   - rows = line items
   - distinct_orders = order count
===================================================== */

SELECT
  COUNT(*) AS rows,
  COUNT(DISTINCT row_id) AS distinct_row_id,
  COUNT(DISTINCT order_id) AS distinct_orders,
  COUNT(DISTINCT order_id || '-' || item_id) AS order_item_pairs
FROM coffee.v_sales_typed;

SELECT order_id, COUNT(*) AS items_in_order
FROM coffee.v_sales_typed
GROUP BY order_id
ORDER BY COUNT(*) DESC;


/* =====================================================
6. CORE BUSINESS KPIs
===================================================== */

SELECT
  COUNT(DISTINCT order_id) AS total_orders,
  SUM(quantity)           AS total_items_sold,
  ROUND(SUM(revenue), 2)  AS total_revenue,
  ROUND(SUM(total_cost), 2) AS total_cost,
  ROUND(SUM(contribution), 2) AS total_profit,
  ROUND(SUM(contribution) / SUM(revenue) * 100, 2) AS gross_margin_pct,
  ROUND(SUM(revenue) / COUNT(DISTINCT order_id), 2) AS avg_order_value
FROM coffee.v_sales_typed;

SELECT
  COUNT(DISTINCT order_id)                         AS total_orders,
  SUM(quantity)                                    AS total_items_sold,
  ROUND(SUM(revenue), 2)                           AS total_revenue,
  ROUND(SUM(total_cost), 2)                        AS total_cost,
  ROUND(SUM(contribution), 2)                      AS total_profit,
  ROUND(SUM(contribution) / NULLIF(SUM(revenue),0) * 100, 2) AS gross_margin_pct,
  ROUND(SUM(revenue) / NULLIF(COUNT(DISTINCT order_id),0), 2) AS avg_order_value,
  ROUND(SUM(quantity) / NULLIF(COUNT(DISTINCT order_id),0), 2) AS avg_items_per_order
FROM coffee.v_sales_typed;

/* =====================================================
7. SALES BY DAY OF WEEK
===================================================== */

SELECT
  day_of_week,
  COUNT(DISTINCT order_id)              AS orders,
  SUM(quantity)                         AS items_sold,
  ROUND(SUM(revenue), 2)                AS revenue,
  ROUND(SUM(contribution), 2)           AS profit,
  ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100, 2) AS margin_pct
FROM coffee.v_sales_typed
GROUP BY day_of_week
ORDER BY revenue DESC;

/* =====================================================
8. SALES BY SHIFT (Morning/Afternoon/Evening etc.)
===================================================== */

SELECT
  shift_bucket,
  COUNT(DISTINCT order_id)              AS orders,
  SUM(quantity)                         AS items_sold,
  ROUND(SUM(revenue), 2)                AS revenue,
  ROUND(SUM(contribution), 2)           AS profit,
  ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100, 2) AS margin_pct
FROM coffee.v_sales_typed
GROUP BY shift_bucket
ORDER BY revenue DESC;

/* =====================================================
9. TOP ITEMS (by revenue)
===================================================== */

SELECT
  item_name,
  item_cat,
  item_size,
  SUM(quantity)                         AS qty,
  ROUND(SUM(revenue), 2)                AS revenue,
  ROUND(SUM(contribution), 2)           AS profit,
  ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100, 2) AS margin_pct
FROM coffee.v_sales_typed
GROUP BY item_name, item_cat, item_size
ORDER BY revenue DESC
LIMIT 15;

/* =====================================================
10. SALES BY CATEGORY
===================================================== */

SELECT
  item_cat,
  COUNT(DISTINCT order_id)                    AS orders,
  SUM(quantity)                               AS items_sold,
  ROUND(SUM(revenue), 2)                      AS revenue,
  ROUND(SUM(contribution), 2)                 AS profit,
  ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100, 2) AS margin_pct
FROM coffee.v_sales_typed
GROUP BY item_cat
ORDER BY revenue DESC;

/* =====================================================
11. CATEGORY × SHIFT PERFORMANCE
===================================================== */

SELECT
  shift_bucket,
  item_cat,
  COUNT(DISTINCT order_id)              AS orders,
  SUM(quantity)                         AS items_sold,
  ROUND(SUM(revenue), 2)                AS revenue,
  ROUND(SUM(contribution), 2)           AS profit,
  ROUND(SUM(contribution) / NULLIF(SUM(revenue),0) * 100, 2) AS margin_pct,
  ROUND(SUM(revenue) / NULLIF(COUNT(DISTINCT order_id),0), 2) AS avg_order_value
FROM coffee.v_sales_typed
GROUP BY shift_bucket, item_cat
ORDER BY shift_bucket, revenue DESC;

/* =====================================================
12. ITEM SIZE & PRICING EFFICIENCY
===================================================== */

SELECT
    item_size,
    COUNT(DISTINCT order_id)                    AS orders,
    SUM(quantity)                               AS items_sold,
    ROUND(SUM(revenue), 2)                      AS revenue,
    ROUND(SUM(contribution), 2)                 AS profit,
    ROUND(SUM(contribution) / NULLIF(SUM(revenue),0) * 100, 2) AS margin_pct,
    ROUND(SUM(revenue) / NULLIF(SUM(quantity),0), 2)         AS avg_price_per_item
FROM coffee.v_sales_typed
GROUP BY item_size
ORDER BY revenue DESC;

/* =====================================================
13. PRODUCT PROFITABILITY (Stars vs Dogs)
===================================================== */

SELECT
    item_name,
    item_cat,
    item_size,
    SUM(quantity)                           AS units_sold,
    ROUND(SUM(revenue), 2)                  AS revenue,
    ROUND(SUM(contribution), 2)             AS profit,
    ROUND(SUM(contribution) / NULLIF(SUM(revenue),0) * 100, 2) AS margin_pct,
    ROUND(SUM(contribution) / NULLIF(SUM(quantity),0), 2)    AS profit_per_unit
FROM coffee.v_sales_typed
GROUP BY item_name, item_cat, item_size
ORDER BY profit DESC;

/* =====================================================
14. CUSTOMER BEHAVIOR (Dine-in vs Take-away)
===================================================== */
SELECT
    in_or_out,
    COUNT(DISTINCT order_id)                    AS orders,
    SUM(quantity)                               AS items_sold,
    ROUND(SUM(revenue), 2)                      AS revenue,
    ROUND(SUM(contribution), 2)                 AS profit,
    ROUND(SUM(contribution) / NULLIF(SUM(revenue),0) * 100, 2) AS margin_pct,
    ROUND(SUM(revenue) / NULLIF(COUNT(DISTINCT order_id),0), 2) AS avg_order_value,
    ROUND(SUM(quantity) / NULLIF(COUNT(DISTINCT order_id),0), 2) AS avg_items_per_order
FROM coffee.v_sales_typed
GROUP BY in_or_out
ORDER BY revenue DESC;

/* =====================================================
15. PEAK HOURS (Operational Load: orders, items, revenue, profit)
===================================================== */

SELECT
  order_hour,
  COUNT(DISTINCT order_id)              AS orders,
  SUM(quantity)                         AS items_sold,
  ROUND(SUM(revenue), 2)                AS revenue,
  ROUND(SUM(contribution), 2)           AS profit,
  ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100, 2) AS margin_pct,
  ROUND(SUM(revenue)/NULLIF(COUNT(DISTINCT order_id),0), 2) AS avg_order_value
FROM coffee.v_sales_typed
GROUP BY order_hour
ORDER BY orders DESC;

/* =====================================================
16. PROFITABILITY RISK — LOW MARGIN & LOSS ITEMS
===================================================== */

SELECT
  item_name,
  item_cat,
  item_size,
  SUM(quantity)                            AS units_sold,
  ROUND(SUM(revenue), 2)                   AS revenue,
  ROUND(SUM(contribution), 2)              AS profit,
  ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100, 2) AS margin_pct,
  ROUND(SUM(contribution)/NULLIF(SUM(quantity),0), 2)   AS profit_per_unit
FROM coffee.v_sales_typed
GROUP BY item_name, item_cat, item_size
HAVING ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100, 2) < 80
   OR SUM(contribution) < 0
ORDER BY margin_pct ASC, profit ASC;


/* =====================================================
17. PROFIT CONCENTRATION — PARETO ANALYSIS
===================================================== */

WITH item_profit AS (
    SELECT
        item_name,
        item_cat,
        item_size,
        ROUND(SUM(contribution), 2) AS profit
    FROM coffee.v_sales_typed
    GROUP BY item_name, item_cat, item_size
),
ranked AS (
    SELECT
        *,
        SUM(profit) OVER () AS total_profit,
        SUM(profit) OVER (ORDER BY profit DESC) AS running_profit
    FROM item_profit
)
SELECT
    item_name,
    item_cat,
    item_size,
    profit,
    ROUND(profit / total_profit * 100, 2) AS pct_of_total_profit,
    ROUND(running_profit / total_profit * 100, 2) AS cumulative_profit_pct
FROM ranked
ORDER BY profit DESC;


/* =====================================================
18. EXECUTIVE INSIGHTS LAYER
   Management-ready decision tables
===================================================== */

/* 18A. Profit Concentration */

WITH item_profit AS (
    SELECT
        item_name,
        item_cat,
        item_size,
        ROUND(SUM(contribution), 2) AS profit
    FROM coffee.v_sales_typed
    GROUP BY item_name, item_cat, item_size
),
tot AS (
    SELECT SUM(profit) AS total_profit FROM item_profit
),
ranked AS (
    SELECT
        i.*,
        t.total_profit,
        SUM(i.profit) OVER (ORDER BY i.profit DESC) AS running_profit
    FROM item_profit i
    CROSS JOIN tot t
)
SELECT
    item_name,
    item_cat,
    item_size,
    profit,
    ROUND(profit / total_profit * 100, 2) AS pct_of_total_profit,
    ROUND(running_profit / total_profit * 100, 2) AS cumulative_profit_pct,
    CASE
        WHEN running_profit / total_profit <= 0.80 THEN 'Core Profit Drivers'
        ELSE 'Long Tail'
    END AS profit_segment
FROM ranked
ORDER BY profit DESC;

/* 18B. Strategic Item Matrix */

WITH item_perf AS (
    SELECT
        item_name,
        item_cat,
        item_size,
        SUM(quantity) AS units_sold,
        ROUND(SUM(revenue),2) AS revenue,
        ROUND(SUM(contribution),2) AS profit,
        ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100,2) AS margin_pct
    FROM coffee.v_sales_typed
    GROUP BY item_name, item_cat, item_size
),
benchmarks AS (
    SELECT
        AVG(units_sold) AS avg_units,
        AVG(margin_pct) AS avg_margin
    FROM item_perf
)
SELECT
    i.*,
    CASE
        WHEN i.units_sold >= b.avg_units AND i.margin_pct >= b.avg_margin THEN 'Star'
        WHEN i.units_sold >= b.avg_units AND i.margin_pct <  b.avg_margin THEN 'Volume Driver'
        WHEN i.units_sold <  b.avg_units AND i.margin_pct >= b.avg_margin THEN 'High Margin Niche'
        ELSE 'Weak Performer'
    END AS item_strategy
FROM item_perf i
CROSS JOIN benchmarks b
ORDER BY profit DESC;

/* 18C. Profit by Hour */

SELECT
    order_hour,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(revenue),2) AS revenue,
    ROUND(SUM(contribution),2) AS profit,
    ROUND(SUM(contribution)/SUM(revenue)*100,2) AS margin_pct
FROM coffee.v_sales_typed
GROUP BY order_hour
ORDER BY profit DESC;

/* 18D. Category Investment Map */

SELECT
    item_cat,
    COUNT(DISTINCT order_id) AS orders,
    SUM(quantity) AS units,
    ROUND(SUM(revenue),2) AS revenue,
    ROUND(SUM(contribution),2) AS profit,
    ROUND(SUM(contribution)/SUM(revenue)*100,2) AS margin_pct
FROM coffee.v_sales_typed
GROUP BY item_cat
ORDER BY profit DESC;

/* 18E. Size Strategy */

SELECT
    item_size,
    COUNT(DISTINCT order_id) AS orders,
    SUM(quantity) AS units,
    ROUND(SUM(revenue),2) AS revenue,
    ROUND(SUM(contribution),2) AS profit,
    ROUND(SUM(contribution)/SUM(revenue)*100,2) AS margin_pct,
    ROUND(SUM(revenue)/SUM(quantity),2) AS avg_price
FROM coffee.v_sales_typed
GROUP BY item_size
ORDER BY profit DESC;

/*18A View: Profit Concentration*/

CREATE OR REPLACE VIEW coffee.v_exec_profit_concentration AS
WITH item_profit AS (
    SELECT
        item_name,
        item_cat,
        item_size,
        ROUND(SUM(contribution), 2) AS profit
    FROM coffee.v_sales_typed
    GROUP BY item_name, item_cat, item_size
),
tot AS (
    SELECT SUM(profit) AS total_profit FROM item_profit
),
ranked AS (
    SELECT
        i.*,
        t.total_profit,
        SUM(i.profit) OVER (ORDER BY i.profit DESC) AS running_profit
    FROM item_profit i
    CROSS JOIN tot t
)
SELECT
    item_name,
    item_cat,
    item_size,
    profit,
    ROUND(profit / total_profit * 100, 2) AS pct_of_total_profit,
    ROUND(running_profit / total_profit * 100, 2) AS cumulative_profit_pct,
    CASE
        WHEN running_profit / total_profit <= 0.80 THEN 'Core Profit Drivers'
        ELSE 'Long Tail'
    END AS profit_segment
FROM ranked
ORDER BY profit DESC;

/*18B View: Strategic Item Matrix*/

CREATE OR REPLACE VIEW coffee.v_exec_item_strategy_matrix AS
WITH item_perf AS (
    SELECT
        item_name,
        item_cat,
        item_size,
        SUM(quantity) AS units_sold,
        ROUND(SUM(revenue),2) AS revenue,
        ROUND(SUM(contribution),2) AS profit,
        ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100,2) AS margin_pct
    FROM coffee.v_sales_typed
    GROUP BY item_name, item_cat, item_size
),
benchmarks AS (
    SELECT
        AVG(units_sold) AS avg_units,
        AVG(margin_pct) AS avg_margin
    FROM item_perf
)
SELECT
    i.*,
    CASE
        WHEN i.units_sold >= b.avg_units AND i.margin_pct >= b.avg_margin THEN 'Star'
        WHEN i.units_sold >= b.avg_units AND i.margin_pct <  b.avg_margin THEN 'Volume Driver'
        WHEN i.units_sold <  b.avg_units AND i.margin_pct >= b.avg_margin THEN 'High Margin Niche'
        ELSE 'Weak Performer'
    END AS item_strategy
FROM item_perf i
CROSS JOIN benchmarks b
ORDER BY profit DESC;

/*18C View: Profit by Hour*/

CREATE OR REPLACE VIEW coffee.v_exec_profit_by_hour AS
SELECT
    order_hour,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(revenue),2) AS revenue,
    ROUND(SUM(contribution),2) AS profit,
    ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100,2) AS margin_pct
FROM coffee.v_sales_typed
GROUP BY order_hour
ORDER BY profit DESC;

/*18D View: Category Investment Map */

CREATE OR REPLACE VIEW coffee.v_exec_category_investment_map AS
SELECT
    item_cat,
    COUNT(DISTINCT order_id) AS orders,
    SUM(quantity) AS units,
    ROUND(SUM(revenue),2) AS revenue,
    ROUND(SUM(contribution),2) AS profit,
    ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100,2) AS margin_pct
FROM coffee.v_sales_typed
GROUP BY item_cat
ORDER BY profit DESC;

/* 18E View: Size Strategy */

CREATE OR REPLACE VIEW coffee.v_exec_size_strategy AS
SELECT
    item_size,
    COUNT(DISTINCT order_id) AS orders,
    SUM(quantity) AS units,
    ROUND(SUM(revenue),2) AS revenue,
    ROUND(SUM(contribution),2) AS profit,
    ROUND(SUM(contribution)/NULLIF(SUM(revenue),0)*100,2) AS margin_pct,
    ROUND(SUM(revenue)/NULLIF(SUM(quantity),0),2) AS avg_price
FROM coffee.v_sales_typed
GROUP BY item_size
ORDER BY profit DESC;

/*exec_category_summary*/

CREATE OR REPLACE VIEW coffee.v_exec_category_summary AS
SELECT
  item_cat,
  COUNT(DISTINCT order_id) AS orders,
  SUM(quantity) AS units_sold,
  ROUND(SUM(revenue), 2) AS revenue,
  ROUND(SUM(total_cost), 2) AS total_cost,
  ROUND(SUM(contribution), 2) AS profit,
  ROUND(SUM(contribution) / NULLIF(SUM(revenue),0) * 100, 2) AS margin_pct,
  ROUND(SUM(revenue) / NULLIF(COUNT(DISTINCT order_id),0), 2) AS avg_order_value
FROM coffee.v_sales_typed
GROUP BY item_cat
ORDER BY profit DESC;


/* =====================================================
EXECUTIVE INSIGHTS VIEWS (ready for Power BI / Python)
=====================================================

coffee.v_exec_category_investment_map
coffee.v_exec_category_summary 
coffee.v_exec_item_strategy_matrix
coffee.v_exec_profit_by_hour
coffee.v_exec_profit_concentration
coffee.v_exec_size_strategy
coffee.v_sales_typed

===================================================== */