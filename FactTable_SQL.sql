/* Assumptions
   - DimDate(date_key, calendar_date, year, month, weekday)
   - DimEmployee(employee_key, employee_id, hire_date, termination_date, company_id)
   - DimCompany(company_key, company_id, company_name)
   - DimLeaveType(leave_type_key, code)
   - DimLeaveStatus(leave_status_key, code)
   - Source tables: Employee, LeaveRequest, LeaveDay.
*/
/* 1) Create the fact table */
CREATE TABLE dbo.FactHeadcountDaily (
    fact_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    date_key INT NOT NULL,
    employee_key INT NOT NULL,
    company_key INT NOT NULL,
    active_flag BIT NOT NULL,
    std_hours_per_day DECIMAL(5,2) NOT NULL,
    leave_day_flag BIT NOT NULL,
    leave_hours DECIMAL(6,2) NULL,
    leave_status_key INT NULL,
    leave_type_key INT NULL,
    termination_flag BIT NOT NULL
);

/* 2) Populate the fact table */
WITH
base AS (
  SELECT
    d.date_key,
    de.employee_key,
    dc.company_key,
    CAST(CASE WHEN e.HireDate <= d.calendar_date AND (e.TerminationDate IS NULL OR d.calendar_date < e.TerminationDate)
              THEN 1
			  ELSE 0
		END AS BIT) AS active_flag,
    e.StandardHoursPerDay AS std_hours_per_day,
    CAST(0 AS BIT) AS leave_day_flag,
    CAST(NULL AS DECIMAL(6,2)) AS leave_hours,
    NULL AS leave_status_key,
    NULL AS leave_type_key,
    CAST(CASE WHEN e.TerminationDate IS NOT NULL AND d.calendar_date = e.TerminationDate
              THEN 1
			  ELSE 0
		END AS BIT) AS termination_flag
  FROM DimEmployee de
  JOIN Employee e ON e.EmployeeID = de.employee_id
  JOIN DimCompany dc ON dc.company_id = e.CompanyID
  JOIN DimDate d ON d.calendar_date BETWEEN e.HireDate AND ISNULL(e.TerminationDate, '9999-12-31')
),
/* Attach leave days */
lv AS (
  SELECT
    d.date_key,
    de.employee_key,
    MAX(CASE WHEN dls.leave_status_key IS NOT NULL
			 THEN 1
			 ELSE 0
		END) AS leave_day_flag,
    SUM(CASE WHEN ld.StatusCode = 'VALID'
			 THEN ld.Hours
			 ELSE 0
		END) AS leave_hours,
    MAX(dls.leave_status_key) AS leave_status_key,
    MAX(dlt.leave_type_key)    AS leave_type_key
  FROM LeaveDay ld
  JOIN LeaveRequest lr ON lr.LeaveRequestID = ld.LeaveRequestID
  JOIN DimDate d ON d.calendar_date = ld.LeaveDate
  JOIN Employee e ON e.EmployeeID = lr.EmployeeID
  JOIN DimEmployee de ON de.employee_id = e.EmployeeID
  LEFT JOIN DimLeaveStatus dls ON dls.code = ld.StatusCode
  LEFT JOIN DimLeaveType dlt ON dlt.code = lr.LeaveTypeCode
  WHERE lr.StatusCode = 'APPROVED'
  GROUP BY d.date_key, de.employee_key
)

INSERT INTO dbo.FactHeadcountDaily (
  date_key, employee_key, company_key,
  active_flag, std_hours_per_day,
  leave_day_flag, leave_hours,
  leave_status_key, leave_type_key,
  termination_flag
)
SELECT
  b.date_key,
  b.employee_key,
  b.company_key,
  b.active_flag,
  b.std_hours_per_day,
  ISNULL(l.leave_day_flag, 0),
  ISNULL(l.leave_hours, 0),
  l.leave_status_key,
  l.leave_type_key,
  b.termination_flag
FROM base b
LEFT JOIN lv l
  ON l.date_key = b.date_key AND l.employee_key = b.employee_key;