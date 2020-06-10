\set ECHO none

-- disable the notices for the create script (shell types etc.)
SET client_min_messages = 'WARNING';
\i tdigest--1.0.0.sql
SET client_min_messages = 'NOTICE';

\set ECHO all

-- SRF function implementing a simple deterministict PRNG

CREATE OR REPLACE FUNCTION prng(nrows int, seed int = 23982, p1 bigint = 16807, p2 bigint = 0, n bigint = 2147483647) RETURNS SETOF double precision AS $$
DECLARE
    val INT := seed;
BEGIN
    FOR i IN 1..nrows LOOP
        val := (val * p1 + p2) % n;

        RETURN NEXT (val::double precision / n);
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION random_normal(nrows int, mean double precision = 0.5, stddev double precision = 0.1, minval double precision = 0.0, maxval double precision = 1.0, seed int = 23982, p1 bigint = 16807, p2 bigint = 0, n bigint = 2147483647) RETURNS SETOF double precision AS $$
DECLARE
    v BIGINT := seed;
    x DOUBLE PRECISION;
    y DOUBLE PRECISION;
    s DOUBLE PRECISION;
    r INT := nrows;
BEGIN

    WHILE true LOOP

        -- random x
        v := (v * p1 + p2) % n;
        x := 2 * v / n::double precision - 1.0;

        -- random y
        v := (v * p1 + p2) % n;
        y := 2 * v / n::double precision - 1.0;

        s := x^2 + y^2;

        IF s != 0.0 AND s < 1.0 THEN

            s = sqrt(-2 * ln(s) / s);

            x := mean + stddev * s * x;

            IF x >= minval AND x <= maxval THEN
                RETURN NEXT x;
                r := r - 1;
            END IF;

            EXIT WHEN r = 0;

            y := mean + stddev * s * y;

            IF y >= minval AND y <= maxval THEN
                RETURN NEXT y;
                r := r - 1;
            END IF;

            EXIT WHEN r = 0;

        END IF;

    END LOOP;

END;
$$ LANGUAGE plpgsql;

-----------------------------------------------------------
-- nice data set with ordered (asc) / evenly-spaced data --
-----------------------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1,1000000) s(i))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1,1000000) s(i)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1,1000000) s(i))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1,1000000) s(i)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1,1000000) s(i))
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1,1000000) s(i)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

------------------------------------------------------------
-- nice data set with ordered (desc) / evenly-spaced data --
------------------------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1000000,1,-1) s(i))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1000000,1,-1) s(i)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1000000,1,-1) s(i))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1000000,1,-1) s(i)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1000000,1,-1) s(i))
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1000000,1,-1) s(i)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

----------------------------------------------------
-- nice data set with random / evenly-spaced data --
----------------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT i / 1000000.0 AS x FROM (SELECT generate_series(1,1000000) AS i, prng(1000000, 49979693) AS x ORDER BY x) foo)
SELECT
    p,
    abs(a - b) < 0.1, -- arbitrary threshold of 10%
    (CASE WHEN abs(a - b) < 0.1 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM (SELECT generate_series(1,1000000) AS i, prng(1000000, 49979693) AS x ORDER BY x) foo),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT i / 1000000.0 AS x FROM (SELECT generate_series(1,1000000) AS i, prng(1000000, 49979693) AS x ORDER BY x) foo)
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM (SELECT generate_series(1,1000000) AS i, prng(1000000, 49979693) AS x ORDER BY x) foo),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT i / 1000000.0 AS x FROM (SELECT generate_series(1,1000000) AS i, prng(1000000, 49979693) AS x ORDER BY x) foo)
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT i / 1000000.0 AS x FROM (SELECT generate_series(1,1000000) AS i, prng(1000000, 49979693) AS x ORDER BY x) foo),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

----------------------------------------------
-- nice data set with random data (uniform) --
----------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT x FROM prng(1000000) s(x))
SELECT
    p,
    abs(a - b) < 0.1, -- arbitrary threshold of 10%
    (CASE WHEN abs(a - b) < 0.1 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT x FROM prng(1000000) s(x)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT x FROM prng(1000000) s(x))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT x FROM prng(1000000) s(x)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT x FROM prng(1000000) s(x))
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT x FROM prng(1000000) s(x)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

--------------------------------------------------
-- nice data set with random data (skewed sqrt) --
--------------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT sqrt(z) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.1, -- arbitrary threshold of 10%
    (CASE WHEN abs(a - b) < 0.1 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT sqrt(z) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT sqrt(z) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT sqrt(z) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT sqrt(z) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT sqrt(z) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-------------------------------------------------------
-- nice data set with random data (skewed sqrt+sqrt) --
-------------------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT sqrt(sqrt(z)) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.1, -- arbitrary threshold of 10%
    (CASE WHEN abs(a - b) < 0.1 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT sqrt(sqrt(z)) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT sqrt(sqrt(z)) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT sqrt(sqrt(z)) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT sqrt(sqrt(z)) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT sqrt(sqrt(z)) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-------------------------------------------------
-- nice data set with random data (skewed pow) --
-------------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT pow(z, 2) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.1, -- arbitrary threshold of 10%
    (CASE WHEN abs(a - b) < 0.1 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 2) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT pow(z, 2) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.005, -- arbitrary threshold of 0.5%
    (CASE WHEN abs(a - b) < 0.005 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 2) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT pow(z, 2) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 2) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;


-----------------------------------------------------
-- nice data set with random data (skewed pow+pow) --
-----------------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT pow(z, 4) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.1, -- arbitrary threshold of 10%
    (CASE WHEN abs(a - b) < 0.1 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 4) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT pow(z, 4) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 4) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT pow(z, 4) AS x FROM prng(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 4) AS x FROM prng(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

----------------------------------------------------------
-- nice data set with random data (normal distribution) --
----------------------------------------------------------

-- 10 centroids (tiny)
WITH data AS (SELECT pow(z, 4) AS x FROM random_normal(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.025, -- arbitrary threshold of 2.5%
    (CASE WHEN abs(a - b) < 0.025 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 10, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 4) AS x FROM random_normal(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 10, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 100 centroids (okay-ish)
WITH data AS (SELECT pow(z, 4) AS x FROM random_normal(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 100, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 4) AS x FROM random_normal(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 100, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- 1000 centroids (very accurate)
WITH data AS (SELECT pow(z, 4) AS x FROM random_normal(1000000) s(z))
SELECT
    p,
    abs(a - b) < 0.001, -- arbitrary threshold of 0.1%
    (CASE WHEN abs(a - b) < 0.001 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(tdigest_percentile(x, 1000, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99])) AS a,
        unnest(percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x)) AS b
    FROM data
) foo;

-- make sure the resulting percentiles are in the right order
WITH data AS (SELECT pow(z, 4) AS x FROM random_normal(1000000) s(z)),
     perc AS (SELECT array_agg((i/100.0)::double precision) AS p FROM generate_series(1,99) s(i))
SELECT * FROM (
    SELECT
        p,
        a,
        LAG(a) OVER (ORDER BY p) AS b
    FROM (
        SELECT
            unnest((SELECT p FROM perc)) AS p,
            unnest(tdigest_percentile(x, 1000, (SELECT p FROM perc))) AS a
        FROM data
    ) foo ) bar WHERE a <= b;

-- some basic tests to verify transforming from and to text work
-- 10 centroids (tiny)
WITH data AS (SELECT i / 1000000.0 AS x FROM generate_series(1,1000000) s(i)),
     intermediate AS (SELECT tdigest(x, 10)::text AS intermediate_x FROM data),
     tdigest_parsed AS (SELECT tdigest_percentile(intermediate_x::tdigest, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS a FROM intermediate),
     pg_percentile AS (SELECT percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x) AS b FROM data)
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(a) AS a,
        unnest(b) AS b
    FROM tdigest_parsed,
         pg_percentile
) foo;

-- verify we can store tdigest in a summary table
CREATE TABLE intermediate_tdigest (grouping int, summary tdigest);

WITH data AS (SELECT row_number() OVER () AS i, pow(z, 4) AS x FROM random_normal(1000000) s(z))
INSERT INTO intermediate_tdigest
SELECT
    i % 10 AS grouping,
    tdigest(x, 100) AS summary
FROM data
GROUP BY i % 10;

WITH data AS (SELECT pow(z, 4) AS x FROM random_normal(1000000) s(z)),
     intermediate AS (SELECT tdigest_percentile(summary, ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS a FROM intermediate_tdigest),
     pg_percentile AS (SELECT percentile_cont(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) WITHIN GROUP (ORDER BY x) AS b FROM data)
SELECT
    p,
    abs(a - b) < 0.01, -- arbitrary threshold of 1%
    (CASE WHEN abs(a - b) < 0.01 THEN NULL ELSE (a - b) END) AS err
FROM (
    SELECT
        unnest(ARRAY[0.01, 0.05, 0.1, 0.9, 0.95, 0.99]) AS p,
        unnest(a) AS a,
        unnest(b) AS b
    FROM intermediate,
         pg_percentile
) foo;
