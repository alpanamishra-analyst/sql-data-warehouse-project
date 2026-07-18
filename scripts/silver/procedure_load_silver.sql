/*
Stored Procedure: Load Silver Layer (Bronze to Silver)
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and clean data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;

Project Credit and Reference: Data With Barra (https://www.datawithbaraa.com/wiki/sql)
===============================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	 DECLARE @start_time DATETIME, 
			 @end_time DATETIME, 
			 @batch_start_time DATETIME, 
			 @batch_end_time DATETIME; 
 BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Silver Layer';
        PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '------------------------------------------------';

  -- Loading silver.crm_cust_info table (Truncate and then Insert Clean Data)
    SET @start_time = GETDATE();
	PRINT'>>Truncating Table: silver.crm_cust_info'
	TRUNCATE TABLE silver.crm_cust_info;  --Truncating table before inserting to ensure re-execution of the script does not create duplicates

	--When using CTE in data cleaning/transformation query, the Insert Statement for clean data needs to be placed only after CTE Statement
	-- Insert & Select together
	PRINT '>>Inserting Data Into: silver.crm_cust_info';
	WITH ranked_customer_ids AS
		(SELECT 
			*,
			ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
			FROM bronze.crm_cust_info 
			WHERE cst_id IS NOT NULL)

	--Insert Cleaned Data into the Silver crm_cust_info table
	INSERT INTO silver.crm_cust_info (
			cst_id,
			cst_key,
			cst_firstname,
			cst_lastname,
			cst_marital_status,
			cst_gndr,
			cst_create_date)

	--This Select is continuation of CTE at the top
	SELECT 
			cst_id,
			cst_key,
			TRIM (cst_firstname) AS cst_firstname,
			TRIM (cst_lastname) AS cst_lastname,
			CASE 
				WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
				WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
				ELSE 'N/A'
			END AS cst_marital_status, --Normalize marital status values to a readable format and also handle nulls in Else statement
			CASE
				WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
				WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
				ELSE 'N/A'
			END AS cst_gndr,  --Normalize Gender values to a readable format and also handle nulls in else statement
			cst_create_date
	FROM ranked_customer_ids
	WHERE flag_last = 1; --Select most recent record per customer
	SET @end_time = GETDATE();
	PRINT '>> Load Duration of Silver crm_cust_info table : ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
    PRINT '>> -------------';
	--===========================================================================================
	-- Loading silver.crm_prd_info
	SET @start_time = GETDATE();
	PRINT'>>Truncating Table: silver.crm_prd_info'
	TRUNCATE TABLE silver.crm_prd_info; 

	--Insert the cleaned and transformed data from below Select query into Silver.crm_prd_info table
	PRINT '>>Inserting Data Into: silver.crm_prd_info';
	INSERT INTO silver.crm_prd_info (
		prd_id,
		cat_id,
		prd_key,
		prd_nm,
		prd_cost,
		prd_line,
		prd_start_dt,
		prd_end_dt
		)

	--Query for Clean data 
	SELECT 
		prd_id,
		REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id, --Extract category Id
		SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key, --Extract Product Key
		prd_nm,
		COALESCE(prd_cost,0) AS prd_cost, --Map product line codes to descriptive values
		CASE UPPER(TRIM(prd_line))
			WHEN 'M' THEN 'Mountain'
			WHEN 'R' THEN 'Road'
			WHEN 'S' THEN  'Other Sales'
			WHEN 'T' THEN 'Touring'
			ELSE 'N/A'
		END AS prd_line,
		CAST(prd_start_dt AS DATE) AS prd_start_dt,  --CASTING from DateTime format to Date, as time is always 00 in raw data hence not required 
		-- SIMPLIFIED: Cast to DATETIME so we can subtract 1, then change back to DATE after Subtraction operation
		CAST(CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) AS DATETIME) - 1 AS DATE) AS prd_end_dt  --Calculate end date as one day before the start date of next record
		FROM bronze.crm_prd_info;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration of Silver.crm_prd_info table : ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
    PRINT '>> -------------';
		--================================================================================================
		-- Loading silver.crm_sales_details
		-- Update the DDL date column data types to match the clean SELECT query
		SET @start_time = GETDATE()
		PRINT'>>Truncating Table: silver.crm_sales_details'
		TRUNCATE TABLE silver.crm_sales_details; 

		--Insert Data into Silver Sales Details column from the clean Select Query
		PRINT '>>Inserting Data Into: silver.crm_sales_details';
		INSERT INTO silver.crm_sales_details(
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			sls_order_dt,
			sls_ship_dt,
			sls_due_dt,
			sls_sales,
			sls_quantity,
			sls_price
			)
		--Select Query for clean data
		SELECT
		  sls_ord_num,
		  sls_prd_key,
		  sls_cust_id,
		  CASE					 --handling invalid data and type casting
			WHEN  sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL 
			ELSE  CAST(CAST(sls_order_dt AS varchar) AS DATE)
		  END AS  sls_order_dt,
		  CASE 
			WHEN   sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
			ELSE  CAST(CAST( sls_ship_dt AS varchar) AS DATE)
		  END AS   sls_ship_dt,
		  CASE 
			WHEN   sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
			ELSE  CAST(CAST( sls_due_dt AS varchar) AS DATE)
		  END AS   sls_due_dt,
		  CASE    --Handling invalid data and Nulls by deriving column values from already existing columns
			WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
			THEN sls_quantity * ABS(sls_price)
			ELSE sls_sales
		  END AS sls_sales, --Recalculate Sales if original value is missing or incorrect
		  sls_quantity,
		  CASE -- Cleanse invalid data by calculating replacement values from existing columns
			WHEN sls_price IS NULL OR sls_price <= 0 
			THEN sls_sales/NULLIF(sls_quantity,0)
			ELSE sls_price
		  END AS sls_price
	  FROM bronze.crm_sales_details;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration of Silver.crm_sales_details table : ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
    PRINT '>> -------------';
	--============================================================================================
	
	SET @start_time = GETDATE();
	PRINT'>>Truncating Table:  silver.erp_cust_az12'
	TRUNCATE TABLE  silver.erp_cust_az12; 
	
	PRINT '>>Inserting Data Into: silver.erp_cust_az12';
	--Insert Cleaned data from Bronze to Silver erp_cust_az12 table. No changes made to table structure/datatypes hence DDL Statement no required again.
	INSERT INTO silver.erp_cust_az12 (
		cid,
		bdate,
		gen)

	--Select query for cleaned data
	SELECT 
		CASE
			WHEN cid LIKE '%NAS%' THEN SUBSTRING(cid, 4, LEN(cid)) --Remove 'NAS' Prefix wherever present
			ELSE cid
		END AS cid,
		CASE 
			WHEN bdate > GETDATE() THEN NULL       --Set BDates greater than current date as NULL
			WHEN bdate < '1915-01-01' THEN NULL    -- Unrealistic past dates (110+ years ago)
			ELSE bdate
		END AS bdate,
		CASE
			WHEN UPPER(TRIM(gen)) IN ('F', 'Female') THEN 'Female'
			WHEN UPPER(TRIM(gen)) IN ('M', 'Male') THEN 'Male'
			ELSE 'N/A'                              --Normalize Gender values and handle unknown cases/missing values
		END AS gen
		FROM bronze.erp_cust_az12;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration of Silver.erp_cust_az12 table : ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
    PRINT '>> -------------';
	
		--=============================================================================================
		SET @start_time = GETDATE();
		PRINT'>>Truncating Table: silver.erp_loc_a101'
		TRUNCATE TABLE silver.erp_loc_a101;
	
		PRINT '>>Inserting Data Into: silver.erp_loc_a101';
		--Insert Cleaned data from Bronze to Silver erp_loc_a101 table. No changes made to table structure/datatypes hence DDL Statement no required again.
		INSERT INTO silver.erp_loc_a101 (
		cid,
		cntry)

		----Select query for cleaned data
		SELECT 
		REPLACE(cid,'-', '') AS cid,
		CASE
			WHEN UPPER(TRIM(cntry)) = 'DE' THEN 'Germany'
			WHEN UPPER(TRIM(cntry)) IN ('US', 'USA') THEN 'United States'
			WHEN UPPER(TRIM(cntry)) = '' OR cntry IS NULL THEN 'N/A'
			ELSE TRIM(cntry)
		END AS cntry
	FROM bronze.erp_loc_a101;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration of Silver.erp_loc_a101 table : ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
    PRINT '>> -------------';

	--============================================================================================
	
	SET @start_time = GETDATE();
	PRINT'>>Truncating Table: silver.erp_px_cat_g1v2'
	TRUNCATE TABLE silver.erp_px_cat_g1v2; 

	--Inserting data into Silver erp_px_cat_g1v2 table
	PRINT '>>Inserting Data Into: silver.erp_px_cat_g1v2';
	INSERT INTO silver.erp_px_cat_g1v2(
		id,
		cat,
		subcat,
		maintenance
		)

	--No cleaning required for any column
	SELECT 
		id,
		cat,
		subcat,
		maintenance
	FROM bronze.erp_px_cat_g1v2;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration of Silver.erp_px_cat_g1v2 table : ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
    PRINT '>> -------------';

		SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Silver Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='
		
	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER'
		PRINT 'Error Message: ' + ERROR_MESSAGE();
		PRINT 'Error Message: ' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message: ' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH
END
--===========================================================================================
