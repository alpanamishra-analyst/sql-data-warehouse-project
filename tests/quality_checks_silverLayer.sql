/*
===============================================================================
Quality Checks
===============================================================================
Script Purpose:
    This script performs various quality checks for data consistency, accuracy, 
    and standardization across the 'silver' layer. It includes checks for:
    - Null or duplicate primary keys.
    - Unwanted spaces in string fields.
    - Data standardization and consistency.
    - Invalid date ranges and orders.
    - Data consistency between related fields.

Usage Notes:
    - Run these checks after data loading Silver Layer.
    - Investigate and resolve any discrepancies found during the checks.

Reference: Data With Barra (https://www.datawithbaraa.com/wiki/sql)
===============================================================================
*/

--===================================================================
--'Silver.crm_cust_info' Table
--================================================================
--Check for Nulls or Duplicates in Primary Key
--Expected Outcome: No Results

SELECT 
	cst_id,
	COUNT(*)
	FROM bronze.crm_cust_info
	GROUP BY cst_id
	HAVING COUNT(*) > 1  OR cst_id IS NULL;

	SELECT *
	FROM bronze.crm_cust_info where cst_key = 'P025';

--Using RANK Window Function, Filter customers with latest creation date (so that older records for that customer as history is not repeated, Primary Key cust_id is unique now)
WITH ranked_customer_ids AS
(SELECT 
	*,
	ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
	FROM bronze.crm_cust_info)
SELECT * FROM ranked_customer_ids
WHERE flag_last = 1;

--check for unwanted spaces in last_name column
--Expected Outcome: No Results 
--If the original value is not equal to the same value after trimmimg. it means there are spaces
--Perform Data Transformation on First Name and Last Name Columns

SELECT cst_lastname
FROM bronze.crm_cust_info
WHERE cst_lastname != TRIM (cst_lastname);

--check for unwanted spaces in gender column
SELECT cst_gndr
FROM bronze.crm_cust_info
WHERE cst_gndr != TRIM (cst_gndr);



--==============================================================================================================
--Quality check of Silver Prd Info Table
	
	SELECT *
	FROM silver.crm_prd_info;

--Using RANK Window Function, Filter customers with latest creation date (so that older records for that customer as history is not repeated, Primary Key cust_id is unique now)
WITH ranked_customer_ids AS
(SELECT 
	*,
	ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
	FROM silver.crm_cust_info)
SELECT * FROM ranked_customer_ids
WHERE flag_last = 1;
=======================================================================

--Check for Nulls or Duplicates in Primary Key
--Expected Outcome: No Results
SELECT 
	prd_id,
	COUNT(*)
	FROM silver.crm_prd_info
	GROUP BY prd_id
	HAVING COUNT(*) > 1  OR prd_id IS NULL;

--check for unwanted spaces in last_name column
--Expected Outcome: No Results 
--If the original value is not equal to the same value after trimmimg. it means there are spaces
--Perform Data Transformation on First Name and Last Name Columns
SELECT cst_lastname
FROM silver.crm_cust_info
WHERE cst_lastname != TRIM (cst_lastname);

--Check for unwanted spaces in gender column
SELECT cst_gndr
FROM silver.crm_cust_info
WHERE cst_gndr != TRIM (cst_gndr);

--Check for Standardization and Consistency
SELECT DISTINCT prd_line
FROM silver.crm_prd_info

--Check for Invalid Date Orders
SELECT *
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt

--Transform the End date Column so each record picks it's end date from the start date of next record
SELECT
prd_id,
prd_key,
prd_nm,
prd_cost,
prd_line,
prd_start_dt,
LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) AS prd_end_dt_test
FROM silver.crm_prd_info
WHERE prd_key IN ('AC-HE-HL-U509', 'AC-HE-HL-U509-R')

--Now CAST the End date to DATETIME in order to subtract 1 from the end date (as Date don't allow this operation) and cast it back to DATE format, so now the end date don't overlap with start date of next record
SELECT
prd_id,
prd_key,
prd_nm,
prd_cost,
prd_line,
prd_start_dt,
CAST(CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) AS DATETIME) -1 AS DATE) AS prd_end_dt_test
FROM silver.crm_prd_info
WHERE prd_key IN ('AC-HE-HL-U509', 'AC-HE-HL-U509-R')

--=================================================================================================================================
--Check for extra Spaces/tabs in the sls_ord_num column using Where filter
--Expected Result: No records found (i.e.column data is clean)
SELECT
  sls_ord_num,
  sls_prd_key,
  sls_cust_id,
  sls_order_dt,
  sls_ship_dt,
  sls_due_dt,
  sls_sales,
  sls_quantity,
  sls_price
  FROM bronze.crm_sales_details
  WHERE sls_ord_num != TRIM(sls_ord_num)

  --Check integrity of sls_prd_key and sls_cust_id columns as these columns are used to connect to other tables
  --To validate this we will check whether there are any records in sales tables that do not exist in product or customer table
  --Expected: No records (i.e. all records present in sales are also present in cust and prod)
  SELECT
  *
  FROM bronze.crm_sales_details
  WHERE  sls_prd_key NOT IN (SELECT prd_key FROM silver.crm_prd_info) 

  SELECT
  *
  FROM bronze.crm_sales_details
  WHERE sls_cust_id NOT IN (SELECT cst_id FROM silver.crm_cust_info) 
  --Result - No records found in above columns, No Transformation needed

--=========================================================================================
  --Now check qualiy of the date columns
  --Here date is present as Integer, hence checking for Negative numbers or Zeros(as negative numbers cannot be cast to date)
  SELECT sls_order_dt 
  FROM bronze.crm_sales_details 
  WHERE sls_order_dt <= 0 

  --Clean the Zeros in order date column to Null
  SELECT NULLIF(sls_order_dt,0) AS sls_order_dt
  FROM bronze.crm_sales_details 
  WHERE sls_order_dt <= 0 

  --Check Length of Date must be 8
  SELECT sls_order_dt 
  FROM bronze.crm_sales_details 
  WHERE LEN(sls_order_dt) !=8

  --Check for Outliers by validating the boundaries of the date range
  SELECT sls_order_dt 
  FROM bronze.crm_sales_details 
  WHERE sls_order_dt >= 20500101 OR sls_order_dt <= 19000101

  --Combining all the above validations in one query
  SELECT 
  NULLIF(sls_order_dt,0) AS sls_order_dt
  FROM bronze.crm_sales_details 
  WHERE sls_order_dt <= 0
  OR LEN(sls_order_dt) != 8
  OR sls_order_dt >= 20500101 
  OR sls_order_dt <= 19000101

  --Validate the same for sls_due_dt column
  SELECT 
  NULLIF(sls_ship_dt,0) AS sls_ship_dt
  FROM bronze.crm_sales_details 
  WHERE sls_ship_dt <= 0
  OR LEN(sls_ship_dt) != 8
  OR sls_ship_dt >= 20500101 
  OR sls_ship_dt <= 19000101

  --Validate the same for sls_due_dt column
  SELECT 
  NULLIF(sls_ship_dt,0) AS sls_ship_dt
  FROM bronze.crm_sales_details 
  WHERE sls_ship_dt <= 0
  OR LEN(sls_ship_dt) != 8
  OR sls_ship_dt >= 20500101 
  OR sls_ship_dt <= 19000101

  --Check that Order date is less than Shipping date or due date. Find only records that have order date higher than shipping/due date
  --Expected Result: No records
  SELECT * 
  FROM bronze.crm_sales_details 
  WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt

  --Business Rule for Sales, Quantity and Price columns
  -- Sales = Quantity * Price 
  -- Sales, Price and Quantity are NOT Negative, Zero or Null
SELECT DISTINCT
	sls_sales,
	sls_quantity,
	sls_price
FROM bronze.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
OR sls_sales IS NULL OR sls_quantity IS NULL
OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price

--Rules
--If Sales is Negative or Zero, derive it using Quantity and Price columns
--If Price is Negativ or Zero, derive it using Quantity and Price columns
--If Price is negative, convert it to a Positive value
SELECT DISTINCT
	sls_sales,
	sls_quantity,
	sls_price
FROM bronze.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
OR sls_sales IS NULL OR sls_quantity IS NULL
OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price

--Cleaning sales, price and quantity columns
SELECT DISTINCT
sls_sales AS old_sales,
sls_quantity,
sls_price AS old_price,
CASE 
	WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
	THEN sls_quantity * ABS(sls_price)
	ELSE sls_sales
END AS sls_sales,
CASE 
	WHEN sls_price IS NULL OR sls_price <= 0 
	THEN sls_sales/NULLIF(sls_quantity,0)
	ELSE sls_price
END AS sls_price
FROM bronze.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
OR sls_sales IS NULL OR sls_quantity IS NULL
OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price

-- Data quality check on the Silver Sales Details table after inserting clean data
SELECT DISTINCT
sls_sales,
sls_quantity,
sls_price
FROM silver.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
OR sls_sales IS NULL OR sls_quantity IS NULL
OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price

SELECT * FROM silver.crm_sales_details
--====================================================================================================================================
--Need to Build Silver Layer
--Clean and Load erp_cust_az12

SELECT
cid,
bdate,
gen
FROM bronze.erp_cust_az12;

select * from silver.crm_cust_info

--In Order to match cid with cst_key from cust_info table, cid needs transformation
SELECT 
CASE
	WHEN cid LIKE '%NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END AS cid
FROM bronze.erp_cust_az12;

--Option 1: Using Not Exists: Cross check the existance of unmatching values of cid column with cst_key column of cust_info table
SELECT 
CASE
	WHEN cid LIKE '%NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END AS cid
FROM bronze.erp_cust_az12
WHERE 
NOT EXISTS (select 1 from silver.crm_cust_info WHERE 
cst_key = CASE
		WHEN cid LIKE '%NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
		ELSE cid
		END)

--Option 2: Using NOT IN: Cross check the existance of unmatching values of cid column with cst_key column of cust_info table
SELECT 
CASE
	WHEN cid LIKE '%NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END AS cid
FROM bronze.erp_cust_az12
WHERE 
CASE
	WHEN cid LIKE '%NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END NOT IN (select cst_key from silver.crm_cust_info WHERE cst_key IS NOT NULL)

--Identify Out of range/Outlier dates for Lower and Upper boundaries
SELECT bdate FROM bronze.erp_cust_az12 WHERE bdate < '1924-01-01'
SELECT bdate FROM bronze.erp_cust_az12 WHERE bdate > GETDATE()

--Clean the Bdate Column
SELECT 
CASE 
	WHEN bdate > GETDATE() THEN NULL
	ELSE bdate
END AS bdate
FROM bronze.erp_cust_az12 ORDER BY bdate ASC --Order by Asc to push the Null to the extreme top of the column as NULL is considered lowest possible value

--Data Standardization & Consistency for gen column
SELECT
CASE
	WHEN UPPER(TRIM(gen)) IN ('F', 'Female') THEN 'Female'
	WHEN UPPER(TRIM(gen)) IN ('M', 'Male') THEN 'Male'
	ELSE 'N/A'
END AS gen
FROM bronze.erp_cust_az12
---------------------------------------------------------------------

--Quality check of Silver_erp_cust_az12 table
SELECT bdate FROM silver.erp_cust_az12 WHERE bdate < '1924-01-01'
SELECT bdate FROM silver.erp_cust_az12 WHERE bdate > GETDATE()
SELECT DISTINCT gen FROM silver.erp_cust_az12
SELECT * FROM silver.erp_cust_az12
--============================================================================================================================

--Analyze and Clean erp_loc_a101 table

SELECT 
cid,
cntry
FROM bronze.erp_loc_a101

SELECT cst_key FROM silver.crm_cust_info

--cid in cust_info table doesn't have a hyphen'-', hence need to fix it
SELECT 
REPLACE(cid,'-', '') AS cid,
cntry
FROM bronze.erp_loc_a101

--Analyze cntry column
SELECT 
DISTINCT cntry
FROM bronze.erp_loc_a101 --Observed lot of abbreviations, empty cells, NULL observed

--Cleaning cntry column
SELECT DISTINCT
CASE 
	WHEN UPPER(TRIM(cntry)) = 'DE' THEN 'Germany'
	WHEN UPPER(TRIM(cntry)) IN ('US', 'USA') THEN 'United States'
	WHEN UPPER(TRIM(cntry)) = '' OR cntry IS NULL THEN 'N/A'
	ELSE TRIM(cntry)
END AS cntry
FROM bronze.erp_loc_a101
-----------------------------------------------------------

--Quality check of Silver.erp_loc_a101 Table
SELECT DISTINCT cntry 
FROM silver.erp_loc_a101

SELECT * FROM  silver.erp_loc_a101

EXEC sp_help 'silver.erp_loc_a101'; -- to confirm detils of third column 'dwh_create_date' from the table 

--================================================================================================================================

SELECT 
id,
cat,
subcat,
maintenance
FROM bronze.erp_px_cat_g1v2

--Check for Unwanted Spaced in various columns
SELECT id, cat, subcat, maintenance
FROM bronze.erp_px_cat_g1v2
WHERE 
cat != TRIM(cat) OR subcat != TRIM(subcat) OR maintenance != TRIM(maintenance) --No results in output confirms that no ounwanted spaces observed in the columns in the output

--Check for Data Standardization and Consistency
SELECT DISTINCT cat FROM bronze.erp_px_cat_g1v2
SELECT DISTINCT subcat FROM bronze.erp_px_cat_g1v2
SELECT DISTINCT maintenance FROM bronze.erp_px_cat_g1v2

------------------------------------------------------------------------

--Quality check 
SELECT * FROM silver.erp_px_cat_g1v2
--==============================================================================================================================
