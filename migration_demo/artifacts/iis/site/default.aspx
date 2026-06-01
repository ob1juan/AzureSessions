<%@ Page Language="C#" Debug="false" %>
<%@ Import Namespace="System" %>
<%@ Import Namespace="System.Configuration" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Globalization" %>
<%@ Import Namespace="System.Text" %>
<script runat="server">
    string message = "";
    string error = "";
    string view = "catalog";

    protected void Page_Load(object sender, EventArgs e)
    {
        view = CleanView(Request["view"]);

        if (Request.HttpMethod == "POST")
        {
            try
            {
                ProcessAction();
            }
            catch (Exception ex)
            {
                error = ex.Message;
            }
        }
    }

    string CleanView(string requestedView)
    {
        string value = (requestedView ?? "catalog").ToLowerInvariant();
        if (value == "products" || value == "customers" || value == "orders" || value == "reports")
        {
            return value;
        }
        return "catalog";
    }

    SqlConnection OpenConnection()
    {
        SqlConnection connection = new SqlConnection(ConfigurationManager.ConnectionStrings["ArcBoxSql"].ConnectionString);
        connection.Open();
        return connection;
    }

    DataTable Query(string sql, params SqlParameter[] parameters)
    {
        DataTable table = new DataTable();
        using (SqlConnection connection = OpenConnection())
        using (SqlCommand command = new SqlCommand(sql, connection))
        using (SqlDataAdapter adapter = new SqlDataAdapter(command))
        {
            foreach (SqlParameter parameter in parameters)
            {
                command.Parameters.Add(parameter);
            }
            adapter.Fill(table);
        }
        return table;
    }

    object Scalar(string sql, params SqlParameter[] parameters)
    {
        using (SqlConnection connection = OpenConnection())
        using (SqlCommand command = new SqlCommand(sql, connection))
        {
            foreach (SqlParameter parameter in parameters)
            {
                command.Parameters.Add(parameter);
            }
            return command.ExecuteScalar();
        }
    }

    int ScalarInt(string sql, params SqlParameter[] parameters)
    {
        object value = Scalar(sql, parameters);
        if (value == null || value == DBNull.Value)
        {
            return 0;
        }
        return Convert.ToInt32(value, CultureInfo.InvariantCulture);
    }

    void Execute(string sql, params SqlParameter[] parameters)
    {
        using (SqlConnection connection = OpenConnection())
        using (SqlCommand command = new SqlCommand(sql, connection))
        {
            foreach (SqlParameter parameter in parameters)
            {
                command.Parameters.Add(parameter);
            }
            command.ExecuteNonQuery();
        }
    }

    SqlParameter Param(string name, SqlDbType type, object value)
    {
        SqlParameter parameter = new SqlParameter(name, type);
        parameter.Value = value ?? DBNull.Value;
        return parameter;
    }

    SqlParameter TextParam(string name, int size, string value)
    {
        SqlParameter parameter = new SqlParameter(name, SqlDbType.NVarChar, size);
        parameter.Value = String.IsNullOrWhiteSpace(value) ? (object)DBNull.Value : value.Trim();
        return parameter;
    }

    string RequiredText(string key, string label)
    {
        string value = (Request.Form[key] ?? "").Trim();
        if (value.Length == 0)
        {
            throw new Exception(label + " is required.");
        }
        return value;
    }

    int RequiredInt(string key, string label)
    {
        int value;
        if (!Int32.TryParse(Request.Form[key], NumberStyles.Integer, CultureInfo.InvariantCulture, out value))
        {
            throw new Exception(label + " must be a whole number.");
        }
        return value;
    }

    int OptionalInt(string key)
    {
        int value;
        if (!Int32.TryParse(Request.Form[key], NumberStyles.Integer, CultureInfo.InvariantCulture, out value))
        {
            return 0;
        }
        return value;
    }

    decimal RequiredMoney(string key, string label)
    {
        decimal value;
        if (!Decimal.TryParse(Request.Form[key], NumberStyles.Number, CultureInfo.InvariantCulture, out value))
        {
            throw new Exception(label + " must be numeric.");
        }
        return value;
    }

    void ProcessAction()
    {
        string action = Request.Form["action"] ?? "";

        if (action == "saveProduct")
        {
            SaveProduct();
            view = "products";
            message = "Product saved.";
        }
        else if (action == "retireProduct")
        {
            RetireProduct();
            view = "products";
            message = "Product retired from the catalog.";
        }
        else if (action == "saveCustomer")
        {
            SaveCustomer();
            view = "customers";
            message = "Customer saved.";
        }
        else if (action == "saveAddress")
        {
            SaveAddress();
            view = "customers";
            message = "Customer address saved.";
        }
        else if (action == "createOrder")
        {
            CreateOrder();
            view = "orders";
            message = "Order created.";
        }
        else if (action == "updateOrderStatus")
        {
            UpdateOrderStatus();
            view = "orders";
            message = "Order status updated.";
        }
    }

    void SaveProduct()
    {
        int productId = OptionalInt("ProductID");
        string name = RequiredText("Name", "Product name");
        string productNumber = RequiredText("ProductNumber", "Product number");
        string modelName = RequiredText("ModelName", "Product model");
        string description = RequiredText("Description", "Description");
        int categoryId = RequiredInt("ProductCategoryID", "Category");
        decimal listPrice = RequiredMoney("ListPrice", "List price");
        decimal standardCost = Decimal.Round(listPrice * 0.55m, 2);
        int modelId = EnsureProductModel(modelName, description);

        if (productId > 0)
        {
            Execute(@"UPDATE SalesLT.Product
SET Name = @Name,
    ProductNumber = @ProductNumber,
    Color = @Color,
    StandardCost = @StandardCost,
    ListPrice = @ListPrice,
    Size = @Size,
    Weight = @Weight,
    ProductCategoryID = @ProductCategoryID,
    ProductModelID = @ProductModelID,
    SellEndDate = NULL,
    ModifiedDate = GETDATE()
WHERE ProductID = @ProductID;",
                Param("@ProductID", SqlDbType.Int, productId),
                TextParam("@Name", 50, name),
                TextParam("@ProductNumber", 25, productNumber),
                TextParam("@Color", 15, Request.Form["Color"]),
                Param("@StandardCost", SqlDbType.Money, standardCost),
                Param("@ListPrice", SqlDbType.Money, listPrice),
                TextParam("@Size", 5, Request.Form["Size"]),
                Param("@Weight", SqlDbType.Decimal, ParseNullableDecimal(Request.Form["Weight"])),
                Param("@ProductCategoryID", SqlDbType.Int, categoryId),
                Param("@ProductModelID", SqlDbType.Int, modelId));
        }
        else
        {
            Execute(@"INSERT SalesLT.Product (Name, ProductNumber, Color, StandardCost, ListPrice, Size, Weight, ProductCategoryID, ProductModelID, SellStartDate)
VALUES (@Name, @ProductNumber, @Color, @StandardCost, @ListPrice, @Size, @Weight, @ProductCategoryID, @ProductModelID, GETDATE());",
                TextParam("@Name", 50, name),
                TextParam("@ProductNumber", 25, productNumber),
                TextParam("@Color", 15, Request.Form["Color"]),
                Param("@StandardCost", SqlDbType.Money, standardCost),
                Param("@ListPrice", SqlDbType.Money, listPrice),
                TextParam("@Size", 5, Request.Form["Size"]),
                Param("@Weight", SqlDbType.Decimal, ParseNullableDecimal(Request.Form["Weight"])),
                Param("@ProductCategoryID", SqlDbType.Int, categoryId),
                Param("@ProductModelID", SqlDbType.Int, modelId));
        }
    }

    decimal? ParseNullableDecimal(string raw)
    {
        decimal value;
        if (Decimal.TryParse(raw, NumberStyles.Number, CultureInfo.InvariantCulture, out value))
        {
            return value;
        }
        return null;
    }

    int EnsureProductModel(string modelName, string description)
    {
        int modelId = ScalarInt("SELECT ProductModelID FROM SalesLT.ProductModel WHERE Name = @Name;", TextParam("@Name", 50, modelName));
        if (modelId == 0)
        {
            modelId = ScalarInt(@"INSERT SalesLT.ProductModel (Name, CatalogDescription) VALUES (@Name, @Description);
SELECT CONVERT(int, SCOPE_IDENTITY());",
                TextParam("@Name", 50, modelName),
                TextParam("@Description", 4000, description));
        }

        int descriptionId = ScalarInt("SELECT ProductDescriptionID FROM SalesLT.ProductDescription WHERE Description = @Description;", TextParam("@Description", 400, description));
        if (descriptionId == 0)
        {
            descriptionId = ScalarInt(@"INSERT SalesLT.ProductDescription (Description) VALUES (@Description);
SELECT CONVERT(int, SCOPE_IDENTITY());",
                TextParam("@Description", 400, description));
        }

        Execute(@"IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductModelProductDescription WHERE ProductModelID = @ModelID AND ProductDescriptionID = @DescriptionID AND Culture = N'en')
INSERT SalesLT.ProductModelProductDescription (ProductModelID, ProductDescriptionID, Culture) VALUES (@ModelID, @DescriptionID, N'en');",
            Param("@ModelID", SqlDbType.Int, modelId),
            Param("@DescriptionID", SqlDbType.Int, descriptionId));

        return modelId;
    }

    void RetireProduct()
    {
        int productId = RequiredInt("ProductID", "Product");
        Execute("UPDATE SalesLT.Product SET SellEndDate = GETDATE(), ModifiedDate = GETDATE() WHERE ProductID = @ProductID;", Param("@ProductID", SqlDbType.Int, productId));
    }

    void SaveCustomer()
    {
        int customerId = OptionalInt("CustomerID");
        string firstName = RequiredText("FirstName", "First name");
        string lastName = RequiredText("LastName", "Last name");
        string emailAddress = RequiredText("EmailAddress", "Email address");

        if (customerId > 0)
        {
            Execute(@"UPDATE SalesLT.Customer
SET FirstName = @FirstName,
    LastName = @LastName,
    CompanyName = @CompanyName,
    EmailAddress = @EmailAddress,
    Phone = @Phone,
    ModifiedDate = GETDATE()
WHERE CustomerID = @CustomerID;",
                Param("@CustomerID", SqlDbType.Int, customerId),
                TextParam("@FirstName", 50, firstName),
                TextParam("@LastName", 50, lastName),
                TextParam("@CompanyName", 128, Request.Form["CompanyName"]),
                TextParam("@EmailAddress", 50, emailAddress),
                TextParam("@Phone", 25, Request.Form["Phone"]));
        }
        else
        {
            Execute(@"INSERT SalesLT.Customer (FirstName, LastName, CompanyName, EmailAddress, Phone, PasswordHash, PasswordSalt)
VALUES (@FirstName, @LastName, @CompanyName, @EmailAddress, @Phone, 'legacy-demo-hash', 'demo');",
                TextParam("@FirstName", 50, firstName),
                TextParam("@LastName", 50, lastName),
                TextParam("@CompanyName", 128, Request.Form["CompanyName"]),
                TextParam("@EmailAddress", 50, emailAddress),
                TextParam("@Phone", 25, Request.Form["Phone"]));
        }
    }

    void SaveAddress()
    {
        int customerId = RequiredInt("CustomerID", "Customer");
        string addressLine1 = RequiredText("AddressLine1", "Address line 1");
        string city = RequiredText("City", "City");
        string stateProvince = RequiredText("StateProvince", "State or province");
        string postalCode = RequiredText("PostalCode", "Postal code");
        string countryRegion = RequiredText("CountryRegion", "Country or region");
        string addressType = RequiredText("AddressType", "Address type");

        int addressId = ScalarInt(@"INSERT SalesLT.Address (AddressLine1, AddressLine2, City, StateProvince, CountryRegion, PostalCode)
VALUES (@AddressLine1, @AddressLine2, @City, @StateProvince, @CountryRegion, @PostalCode);
SELECT CONVERT(int, SCOPE_IDENTITY());",
            TextParam("@AddressLine1", 60, addressLine1),
            TextParam("@AddressLine2", 60, Request.Form["AddressLine2"]),
            TextParam("@City", 30, city),
            TextParam("@StateProvince", 50, stateProvince),
            TextParam("@CountryRegion", 50, countryRegion),
            TextParam("@PostalCode", 15, postalCode));

        Execute(@"IF NOT EXISTS (SELECT 1 FROM SalesLT.CustomerAddress WHERE CustomerID = @CustomerID AND AddressID = @AddressID)
INSERT SalesLT.CustomerAddress (CustomerID, AddressID, AddressType) VALUES (@CustomerID, @AddressID, @AddressType);",
            Param("@CustomerID", SqlDbType.Int, customerId),
            Param("@AddressID", SqlDbType.Int, addressId),
            TextParam("@AddressType", 50, addressType));
    }

    void CreateOrder()
    {
        int customerId = RequiredInt("CustomerID", "Customer");
        int productId = RequiredInt("ProductID", "Product");
        int quantity = RequiredInt("Quantity", "Quantity");
        if (quantity < 1)
        {
            throw new Exception("Quantity must be at least 1.");
        }

        int addressId = ScalarInt("SELECT TOP (1) AddressID FROM SalesLT.CustomerAddress WHERE CustomerID = @CustomerID ORDER BY AddressID;", Param("@CustomerID", SqlDbType.Int, customerId));
        if (addressId == 0)
        {
            throw new Exception("Add an address for the selected customer before creating an order.");
        }

        decimal unitPrice = Convert.ToDecimal(Scalar("SELECT ListPrice FROM SalesLT.Product WHERE ProductID = @ProductID;", Param("@ProductID", SqlDbType.Int, productId)), CultureInfo.InvariantCulture);
        int salesOrderId = ScalarInt(@"INSERT SalesLT.SalesOrderHeader (CustomerID, ShipToAddressID, BillToAddressID, PurchaseOrderNumber, AccountNumber, ShipMethod, Status, Comment)
VALUES (@CustomerID, @AddressID, @AddressID, @PurchaseOrderNumber, @AccountNumber, N'CARGO TRANSPORT 5', 1, N'Created from the legacy Web Forms storefront');
SELECT CONVERT(int, SCOPE_IDENTITY());",
            Param("@CustomerID", SqlDbType.Int, customerId),
            Param("@AddressID", SqlDbType.Int, addressId),
            TextParam("@PurchaseOrderNumber", 25, "WEB-" + DateTime.UtcNow.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture)),
            TextParam("@AccountNumber", 15, "10-4020-WEB"));

        Execute("INSERT SalesLT.SalesOrderDetail (SalesOrderID, ProductID, OrderQty, UnitPrice, UnitPriceDiscount) VALUES (@SalesOrderID, @ProductID, @OrderQty, @UnitPrice, 0);",
            Param("@SalesOrderID", SqlDbType.Int, salesOrderId),
            Param("@ProductID", SqlDbType.Int, productId),
            Param("@OrderQty", SqlDbType.SmallInt, quantity),
            Param("@UnitPrice", SqlDbType.Money, unitPrice));
    }

    void UpdateOrderStatus()
    {
        int salesOrderId = RequiredInt("SalesOrderID", "Order");
        int status = RequiredInt("Status", "Status");
        if (status < 1 || status > 6)
        {
            throw new Exception("Status must be between 1 and 6.");
        }
        Execute(@"UPDATE SalesLT.SalesOrderHeader
SET Status = @Status,
    ShipDate = CASE WHEN @Status >= 5 THEN ISNULL(ShipDate, GETDATE()) ELSE ShipDate END,
    ModifiedDate = GETDATE()
WHERE SalesOrderID = @SalesOrderID;",
            Param("@SalesOrderID", SqlDbType.Int, salesOrderId),
            Param("@Status", SqlDbType.TinyInt, status));
    }

    string H(object value)
    {
        return Server.HtmlEncode(Convert.ToString(value));
    }

    string Money(object value)
    {
        if (value == null || value == DBNull.Value)
        {
            return "$0.00";
        }
        return Convert.ToDecimal(value, CultureInfo.InvariantCulture).ToString("C", CultureInfo.GetCultureInfo("en-US"));
    }

    string DecimalValue(object value)
    {
        if (value == null || value == DBNull.Value)
        {
            return "";
        }
        return Convert.ToDecimal(value, CultureInfo.InvariantCulture).ToString("0.00", CultureInfo.InvariantCulture);
    }

    string Selected(object actual, object expected)
    {
        return Convert.ToString(actual, CultureInfo.InvariantCulture) == Convert.ToString(expected, CultureInfo.InvariantCulture) ? " selected" : "";
    }

    string StatusName(object statusValue)
    {
        int status = Convert.ToInt32(statusValue, CultureInfo.InvariantCulture);
        switch (status)
        {
            case 1: return "In process";
            case 2: return "Approved";
            case 3: return "Backordered";
            case 4: return "Rejected";
            case 5: return "Shipped";
            case 6: return "Cancelled";
            default: return "Unknown";
        }
    }

    DataTable Categories()
    {
        return Query(@"SELECT ProductCategoryID,
       ISNULL(parent.Name + N' / ', N'') + category.Name AS CategoryName
FROM SalesLT.ProductCategory AS category
LEFT JOIN SalesLT.ProductCategory AS parent ON parent.ProductCategoryID = category.ParentProductCategoryID
ORDER BY CategoryName;");
    }

    DataTable Customers()
    {
        return Query(@"SELECT CustomerID, FirstName, LastName, CompanyName, EmailAddress, Phone
FROM SalesLT.Customer
ORDER BY LastName, FirstName;");
    }

    DataTable Products()
    {
        return Query(@"SELECT ProductID, Name, ProductNumber, ListPrice
FROM SalesLT.Product
WHERE SellEndDate IS NULL
ORDER BY Name;");
    }

    string CategoryOptions(object selectedValue)
    {
        StringBuilder html = new StringBuilder();
        foreach (DataRow row in Categories().Rows)
        {
            html.Append("<option value='").Append(H(row["ProductCategoryID"])).Append("'").Append(Selected(row["ProductCategoryID"], selectedValue)).Append(">").Append(H(row["CategoryName"])).Append("</option>");
        }
        return html.ToString();
    }

    string CustomerOptions(object selectedValue)
    {
        StringBuilder html = new StringBuilder();
        foreach (DataRow row in Customers().Rows)
        {
            html.Append("<option value='").Append(H(row["CustomerID"])).Append("'").Append(Selected(row["CustomerID"], selectedValue)).Append(">");
            html.Append(H(row["LastName"])).Append(", ").Append(H(row["FirstName"]));
            if (row["CompanyName"] != DBNull.Value)
            {
                html.Append(" - ").Append(H(row["CompanyName"]));
            }
            html.Append("</option>");
        }
        return html.ToString();
    }

    string ProductOptions(object selectedValue)
    {
        StringBuilder html = new StringBuilder();
        foreach (DataRow row in Products().Rows)
        {
            html.Append("<option value='").Append(H(row["ProductID"])).Append("'").Append(Selected(row["ProductID"], selectedValue)).Append(">");
            html.Append(H(row["Name"])).Append(" - ").Append(Money(row["ListPrice"]));
            html.Append("</option>");
        }
        return html.ToString();
    }

    string NavLink(string targetView, string label)
    {
        string cssClass = view == targetView ? " class='active'" : "";
        return "<a" + cssClass + " href='default.aspx?view=" + H(targetView) + "'>" + H(label) + "</a>";
    }

    string RenderDashboard()
    {
        DataTable stats = Query(@"SELECT
    (SELECT COUNT(*) FROM SalesLT.Product WHERE SellEndDate IS NULL) AS ProductCount,
    (SELECT COUNT(*) FROM SalesLT.Customer) AS CustomerCount,
    (SELECT COUNT(*) FROM SalesLT.SalesOrderHeader) AS OrderCount,
    (SELECT ISNULL(SUM(TotalDue), 0) FROM SalesLT.SalesOrderHeader) AS Revenue;");
        DataRow row = stats.Rows[0];
        return "<section class='metrics'>" +
            "<div><span>Products</span><strong>" + H(row["ProductCount"]) + "</strong></div>" +
            "<div><span>Customers</span><strong>" + H(row["CustomerCount"]) + "</strong></div>" +
            "<div><span>Orders</span><strong>" + H(row["OrderCount"]) + "</strong></div>" +
            "<div><span>Revenue</span><strong>" + Money(row["Revenue"]) + "</strong></div>" +
            "</section>";
    }

    string RenderCurrentView()
    {
        if (view == "products")
        {
            return RenderProducts();
        }
        if (view == "customers")
        {
            return RenderCustomers();
        }
        if (view == "orders")
        {
            return RenderOrders();
        }
        if (view == "reports")
        {
            return RenderReports();
        }
        return RenderCatalog();
    }

    string RenderCatalog()
    {
        string search = (Request["search"] ?? "").Trim();
        int categoryId = 0;
        Int32.TryParse(Request["category"], NumberStyles.Integer, CultureInfo.InvariantCulture, out categoryId);

        DataTable products = Query(@"SELECT p.ProductID, p.Name, p.ProductNumber, p.Color, p.Size, p.ListPrice,
       ISNULL(p.CategoryName, N'Uncategorized') AS CategoryName,
       ISNULL(p.ProductModel, N'Legacy model') AS ProductModel,
       ISNULL(p.Description, N'AdventureWorks catalog item') AS Description
FROM SalesLT.vStorefrontCatalog AS p
WHERE (@CategoryID = 0 OR EXISTS (
        SELECT 1 FROM SalesLT.Product AS source WHERE source.ProductID = p.ProductID AND source.ProductCategoryID = @CategoryID
    ))
  AND (@Search = N'' OR p.Name LIKE N'%' + @Search + N'%' OR p.ProductNumber LIKE N'%' + @Search + N'%' OR p.Description LIKE N'%' + @Search + N'%')
ORDER BY p.CategoryName, p.Name;",
            Param("@CategoryID", SqlDbType.Int, categoryId),
            Param("@Search", SqlDbType.NVarChar, search));

        StringBuilder html = new StringBuilder();
        html.Append("<section class='panel hero'><div><p class='eyebrow'>SQL Server products</p><h2>AdventureWorks storefront</h2><p>Browse products, create orders, and manage customers from a classic ASP.NET Web Forms application running on IIS.</p></div><div class='hero-badge'><strong>").Append(H(Environment.MachineName)).Append("</strong><span>ArcBox-SQL</span></div></section>");
        html.Append("<section class='panel'><form class='filters' method='get'><input type='hidden' name='view' value='catalog' /><label>Search<input name='search' value='").Append(H(search)).Append("' placeholder='bike, helmet, light' /></label><label>Category<select name='category'><option value='0'>All categories</option>").Append(CategoryOptions(categoryId)).Append("</select></label><button type='submit'>Filter</button></form></section>");
        html.Append("<section class='catalog-grid'>");

        foreach (DataRow row in products.Rows)
        {
            html.Append("<article class='product-card'><div><span class='pill'>").Append(H(row["CategoryName"])).Append("</span><h3>").Append(H(row["Name"])).Append("</h3><p>").Append(H(row["Description"])).Append("</p></div>");
            html.Append("<dl><dt>Model</dt><dd>").Append(H(row["ProductModel"])).Append("</dd><dt>Number</dt><dd>").Append(H(row["ProductNumber"])).Append("</dd><dt>Color</dt><dd>").Append(H(row["Color"] == DBNull.Value ? "Any" : row["Color"])).Append("</dd></dl>");
            html.Append("<form method='post' class='quick-order'><input type='hidden' name='action' value='createOrder' /><input type='hidden' name='view' value='orders' /><input type='hidden' name='ProductID' value='").Append(H(row["ProductID"])).Append("' /><strong>").Append(Money(row["ListPrice"])).Append("</strong><select name='CustomerID'>").Append(CustomerOptions(null)).Append("</select><input type='number' name='Quantity' value='1' min='1' /><button type='submit'>Create order</button></form></article>");
        }

        if (products.Rows.Count == 0)
        {
            html.Append("<article class='empty'>No products matched the current filter.</article>");
        }

        html.Append("</section>");
        return html.ToString();
    }

    string RenderProducts()
    {
        DataTable products = Query(@"SELECT p.ProductID, p.Name, p.ProductNumber, p.Color, p.Size, p.Weight, p.ListPrice,
       p.ProductCategoryID, p.SellEndDate, ISNULL(pc.Name, N'Uncategorized') AS CategoryName,
       ISNULL(pm.Name, N'Legacy model') AS ModelName,
       ISNULL(d.Description, N'') AS Description
FROM SalesLT.Product AS p
LEFT JOIN SalesLT.ProductCategory AS pc ON pc.ProductCategoryID = p.ProductCategoryID
LEFT JOIN SalesLT.ProductModel AS pm ON pm.ProductModelID = p.ProductModelID
OUTER APPLY (
    SELECT TOP (1) pd.Description
    FROM SalesLT.ProductModelProductDescription AS x
    INNER JOIN SalesLT.ProductDescription AS pd ON pd.ProductDescriptionID = x.ProductDescriptionID
    WHERE x.ProductModelID = p.ProductModelID
) AS d
ORDER BY CASE WHEN p.SellEndDate IS NULL THEN 0 ELSE 1 END, p.Name;");

        StringBuilder html = new StringBuilder();
        html.Append("<section class='panel'><h2>Product administration</h2><form method='post' class='admin-grid'><input type='hidden' name='action' value='saveProduct' /><input type='hidden' name='view' value='products' />");
        html.Append("<label>Name<input name='Name' maxlength='50' required /></label><label>Product number<input name='ProductNumber' maxlength='25' required /></label><label>Model<input name='ModelName' maxlength='50' required /></label><label>Category<select name='ProductCategoryID'>").Append(CategoryOptions(null)).Append("</select></label>");
        html.Append("<label>Color<input name='Color' maxlength='15' /></label><label>Size<input name='Size' maxlength='5' /></label><label>Weight<input name='Weight' type='number' step='0.01' min='0' /></label><label>List price<input name='ListPrice' type='number' step='0.01' min='0' required /></label><label class='span-all'>Description<input name='Description' maxlength='400' required /></label><button type='submit'>Add product</button></form></section>");
        html.Append("<section class='stack'>");

        foreach (DataRow row in products.Rows)
        {
            string retiredClass = row["SellEndDate"] == DBNull.Value ? "" : " retired";
            html.Append("<article class='edit-card").Append(retiredClass).Append("'><form method='post'><input type='hidden' name='action' value='saveProduct' /><input type='hidden' name='view' value='products' /><input type='hidden' name='ProductID' value='").Append(H(row["ProductID"])).Append("' />");
            html.Append("<div class='edit-heading'><strong>").Append(H(row["Name"])).Append("</strong><span>").Append(H(row["ProductNumber"])).Append("</span></div><div class='admin-grid compact'>");
            html.Append("<label>Name<input name='Name' maxlength='50' value='").Append(H(row["Name"])).Append("' /></label><label>Product number<input name='ProductNumber' maxlength='25' value='").Append(H(row["ProductNumber"])).Append("' /></label><label>Model<input name='ModelName' maxlength='50' value='").Append(H(row["ModelName"])).Append("' /></label><label>Category<select name='ProductCategoryID'>").Append(CategoryOptions(row["ProductCategoryID"])).Append("</select></label>");
            html.Append("<label>Color<input name='Color' maxlength='15' value='").Append(H(row["Color"])).Append("' /></label><label>Size<input name='Size' maxlength='5' value='").Append(H(row["Size"])).Append("' /></label><label>Weight<input name='Weight' type='number' step='0.01' min='0' value='").Append(DecimalValue(row["Weight"])).Append("' /></label><label>List price<input name='ListPrice' type='number' step='0.01' min='0' value='").Append(DecimalValue(row["ListPrice"])).Append("' /></label><label class='span-all'>Description<input name='Description' maxlength='400' value='").Append(H(row["Description"])).Append("' /></label></div><div class='actions'><button type='submit'>Save</button></form>");
            if (row["SellEndDate"] == DBNull.Value)
            {
                html.Append("<form method='post'><input type='hidden' name='action' value='retireProduct' /><input type='hidden' name='view' value='products' /><input type='hidden' name='ProductID' value='").Append(H(row["ProductID"])).Append("' /><button class='secondary' type='submit'>Retire</button></form>");
            }
            html.Append("</div></article>");
        }

        html.Append("</section>");
        return html.ToString();
    }

    string RenderCustomers()
    {
        DataTable customers = Customers();
        DataTable addresses = Query(@"SELECT c.CustomerID, c.FirstName, c.LastName, ca.AddressType, a.AddressLine1, a.AddressLine2, a.City, a.StateProvince, a.CountryRegion, a.PostalCode
FROM SalesLT.Customer AS c
INNER JOIN SalesLT.CustomerAddress AS ca ON ca.CustomerID = c.CustomerID
INNER JOIN SalesLT.Address AS a ON a.AddressID = ca.AddressID
ORDER BY c.LastName, c.FirstName, ca.AddressType;");

        StringBuilder html = new StringBuilder();
        html.Append("<section class='panel'><h2>Customer management</h2><form method='post' class='admin-grid'><input type='hidden' name='action' value='saveCustomer' /><input type='hidden' name='view' value='customers' /><label>First name<input name='FirstName' maxlength='50' required /></label><label>Last name<input name='LastName' maxlength='50' required /></label><label>Company<input name='CompanyName' maxlength='128' /></label><label>Email<input name='EmailAddress' type='email' maxlength='50' required /></label><label>Phone<input name='Phone' maxlength='25' /></label><button type='submit'>Add customer</button></form></section>");
        html.Append("<section class='stack'>");

        foreach (DataRow row in customers.Rows)
        {
            html.Append("<article class='edit-card'><form method='post'><input type='hidden' name='action' value='saveCustomer' /><input type='hidden' name='view' value='customers' /><input type='hidden' name='CustomerID' value='").Append(H(row["CustomerID"])).Append("' /><div class='edit-heading'><strong>").Append(H(row["LastName"])).Append(", ").Append(H(row["FirstName"])).Append("</strong><span>").Append(H(row["EmailAddress"])).Append("</span></div><div class='admin-grid compact'><label>First name<input name='FirstName' maxlength='50' value='").Append(H(row["FirstName"])).Append("' /></label><label>Last name<input name='LastName' maxlength='50' value='").Append(H(row["LastName"])).Append("' /></label><label>Company<input name='CompanyName' maxlength='128' value='").Append(H(row["CompanyName"])).Append("' /></label><label>Email<input name='EmailAddress' type='email' maxlength='50' value='").Append(H(row["EmailAddress"])).Append("' /></label><label>Phone<input name='Phone' maxlength='25' value='").Append(H(row["Phone"])).Append("' /></label></div><div class='actions'><button type='submit'>Save customer</button></div></form></article>");
        }

        html.Append("</section><section class='panel'><h2>Add customer address</h2><form method='post' class='admin-grid'><input type='hidden' name='action' value='saveAddress' /><input type='hidden' name='view' value='customers' /><label>Customer<select name='CustomerID'>").Append(CustomerOptions(null)).Append("</select></label><label>Address type<input name='AddressType' value='Shipping' maxlength='50' required /></label><label>Address line 1<input name='AddressLine1' maxlength='60' required /></label><label>Address line 2<input name='AddressLine2' maxlength='60' /></label><label>City<input name='City' maxlength='30' required /></label><label>State/province<input name='StateProvince' maxlength='50' required /></label><label>Postal code<input name='PostalCode' maxlength='15' required /></label><label>Country/region<input name='CountryRegion' maxlength='50' value='United States' required /></label><button type='submit'>Add address</button></form></section>");
        html.Append("<section class='panel'><h2>Address book</h2><table><tr><th>Customer</th><th>Type</th><th>Address</th><th>City</th><th>Region</th></tr>");
        foreach (DataRow row in addresses.Rows)
        {
            html.Append("<tr><td>").Append(H(row["LastName"])).Append(", ").Append(H(row["FirstName"])).Append("</td><td>").Append(H(row["AddressType"])).Append("</td><td>").Append(H(row["AddressLine1"])).Append(" ").Append(H(row["AddressLine2"])).Append("</td><td>").Append(H(row["City"])).Append("</td><td>").Append(H(row["StateProvince"])).Append(" ").Append(H(row["PostalCode"])).Append("</td></tr>");
        }
        html.Append("</table></section>");
        return html.ToString();
    }

    string RenderOrders()
    {
        DataTable orders = Query(@"SELECT h.SalesOrderID, h.SalesOrderNumber, h.PurchaseOrderNumber, h.OrderDate, h.Status, h.SubTotal, h.TaxAmt, h.Freight, h.TotalDue,
       c.FirstName, c.LastName, c.CompanyName
FROM SalesLT.SalesOrderHeader AS h
INNER JOIN SalesLT.Customer AS c ON c.CustomerID = h.CustomerID
ORDER BY h.SalesOrderID DESC;");

        DataTable details = Query(@"SELECT h.SalesOrderID, p.Name, d.OrderQty, d.UnitPrice, d.LineTotal
FROM SalesLT.SalesOrderDetail AS d
INNER JOIN SalesLT.SalesOrderHeader AS h ON h.SalesOrderID = d.SalesOrderID
INNER JOIN SalesLT.Product AS p ON p.ProductID = d.ProductID
ORDER BY h.SalesOrderID DESC, d.SalesOrderDetailID;");

        StringBuilder html = new StringBuilder();
        html.Append("<section class='panel'><h2>Create order</h2><form method='post' class='admin-grid'><input type='hidden' name='action' value='createOrder' /><input type='hidden' name='view' value='orders' /><label>Customer<select name='CustomerID'>").Append(CustomerOptions(null)).Append("</select></label><label>Product<select name='ProductID'>").Append(ProductOptions(null)).Append("</select></label><label>Quantity<input name='Quantity' type='number' min='1' value='1' required /></label><button type='submit'>Create order</button></form></section>");
        html.Append("<section class='stack'>");
        foreach (DataRow order in orders.Rows)
        {
            html.Append("<article class='order-card'><div class='edit-heading'><strong>").Append(H(order["SalesOrderNumber"])).Append("</strong><span>").Append(H(order["LastName"])).Append(", ").Append(H(order["FirstName"])).Append(" - ").Append(Money(order["TotalDue"])).Append("</span></div><div class='order-meta'><span>PO ").Append(H(order["PurchaseOrderNumber"])).Append("</span><span>").Append(H(Convert.ToDateTime(order["OrderDate"]).ToString("yyyy-MM-dd"))).Append("</span><span>").Append(H(StatusName(order["Status"]))).Append("</span></div>");
            html.Append("<form method='post' class='status-form'><input type='hidden' name='action' value='updateOrderStatus' /><input type='hidden' name='view' value='orders' /><input type='hidden' name='SalesOrderID' value='").Append(H(order["SalesOrderID"])).Append("' /><select name='Status'><option value='1'").Append(Selected(order["Status"], 1)).Append(">In process</option><option value='2'").Append(Selected(order["Status"], 2)).Append(">Approved</option><option value='3'").Append(Selected(order["Status"], 3)).Append(">Backordered</option><option value='4'").Append(Selected(order["Status"], 4)).Append(">Rejected</option><option value='5'").Append(Selected(order["Status"], 5)).Append(">Shipped</option><option value='6'").Append(Selected(order["Status"], 6)).Append(">Cancelled</option></select><button type='submit'>Update</button></form>");
            html.Append("<table><tr><th>Product</th><th>Qty</th><th>Unit</th><th>Total</th></tr>");
            foreach (DataRow detail in details.Select("SalesOrderID = " + Convert.ToString(order["SalesOrderID"], CultureInfo.InvariantCulture)))
            {
                html.Append("<tr><td>").Append(H(detail["Name"])).Append("</td><td>").Append(H(detail["OrderQty"])).Append("</td><td>").Append(Money(detail["UnitPrice"])).Append("</td><td>").Append(Money(detail["LineTotal"])).Append("</td></tr>");
            }
            html.Append("</table></article>");
        }
        html.Append("</section>");
        return html.ToString();
    }

    string RenderReports()
    {
        DataTable categoryRevenue = Query(@"SELECT TOP (10) ISNULL(pc.Name, N'Uncategorized') AS CategoryName, SUM(d.LineTotal) AS Revenue, SUM(d.OrderQty) AS Units
FROM SalesLT.SalesOrderDetail AS d
INNER JOIN SalesLT.Product AS p ON p.ProductID = d.ProductID
LEFT JOIN SalesLT.ProductCategory AS pc ON pc.ProductCategoryID = p.ProductCategoryID
GROUP BY pc.Name
ORDER BY Revenue DESC;");
        DataTable customerRevenue = Query(@"SELECT TOP (10) c.FirstName, c.LastName, c.CompanyName, COUNT(h.SalesOrderID) AS Orders, SUM(h.TotalDue) AS Revenue
FROM SalesLT.Customer AS c
INNER JOIN SalesLT.SalesOrderHeader AS h ON h.CustomerID = c.CustomerID
GROUP BY c.FirstName, c.LastName, c.CompanyName
ORDER BY Revenue DESC;");

        StringBuilder html = new StringBuilder();
        html.Append("<section class='report-grid'><article class='panel'><h2>Revenue by category</h2><table><tr><th>Category</th><th>Units</th><th>Revenue</th></tr>");
        foreach (DataRow row in categoryRevenue.Rows)
        {
            html.Append("<tr><td>").Append(H(row["CategoryName"])).Append("</td><td>").Append(H(row["Units"])).Append("</td><td>").Append(Money(row["Revenue"])).Append("</td></tr>");
        }
        html.Append("</table></article><article class='panel'><h2>Customer revenue</h2><table><tr><th>Customer</th><th>Orders</th><th>Revenue</th></tr>");
        foreach (DataRow row in customerRevenue.Rows)
        {
            html.Append("<tr><td>").Append(H(row["LastName"])).Append(", ").Append(H(row["FirstName"])).Append("</td><td>").Append(H(row["Orders"])).Append("</td><td>").Append(Money(row["Revenue"])).Append("</td></tr>");
        }
        html.Append("</table></article></section>");
        return html.ToString();
    }
</script>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>AdventureWorks Legacy Storefront</title>
    <style>
        :root { --ink: #172026; --muted: #5f6b73; --line: #d7ddd8; --paper: #fbfaf4; --panel: #ffffff; --brand: #0b6b5d; --brand-dark: #084b41; --accent: #d98d1b; --soft: #edf5ef; }
        * { box-sizing: border-box; }
        body { margin: 0; font-family: Georgia, "Times New Roman", serif; color: var(--ink); background: linear-gradient(135deg, #fbfaf4 0%, #eef5ee 48%, #f7ead7 100%); }
        header { padding: 30px clamp(18px, 4vw, 52px) 18px; display: grid; gap: 18px; grid-template-columns: minmax(0, 1fr) auto; align-items: end; }
        h1, h2, h3 { margin: 0; line-height: 1.05; }
        h1 { font-size: clamp(2rem, 5vw, 4.6rem); max-width: 900px; }
        h2 { font-size: clamp(1.4rem, 3vw, 2.2rem); }
        h3 { font-size: 1.1rem; }
        p { color: var(--muted); line-height: 1.55; }
        nav { display: flex; flex-wrap: wrap; gap: 8px; padding: 0 clamp(18px, 4vw, 52px) 24px; }
        nav a, button, .button { border: 1px solid var(--brand); background: var(--panel); color: var(--brand-dark); padding: 10px 14px; border-radius: 7px; text-decoration: none; font-weight: 700; cursor: pointer; font-family: Verdana, sans-serif; font-size: 0.88rem; }
        nav a.active, button { background: var(--brand); color: #fff; }
        button.secondary { background: #fff; color: #8a4b00; border-color: var(--accent); }
        main { padding: 0 clamp(18px, 4vw, 52px) 44px; }
        .system { max-width: 980px; margin: 0 0 16px; padding: 12px 14px; border-radius: 7px; font-family: Verdana, sans-serif; }
        .ok { background: #e8f4ea; border: 1px solid #9ac7a0; color: #155724; }
        .err { background: #fff1ef; border: 1px solid #e5aca5; color: #8a1f11; white-space: pre-wrap; }
        .metrics { display: grid; grid-template-columns: repeat(4, minmax(140px, 1fr)); gap: 12px; margin-bottom: 18px; }
        .metrics div, .panel, .product-card, .edit-card, .order-card, .empty { background: rgba(255,255,255,0.92); border: 1px solid var(--line); border-radius: 8px; box-shadow: 0 10px 30px rgba(20, 37, 31, 0.08); }
        .metrics div { padding: 16px; }
        .metrics span, .eyebrow, .pill, .order-meta, label { font-family: Verdana, sans-serif; font-size: 0.78rem; color: var(--muted); }
        .metrics strong { display: block; margin-top: 8px; font-size: 1.8rem; }
        .panel { padding: clamp(18px, 3vw, 28px); margin-bottom: 18px; }
        .hero { display: grid; grid-template-columns: minmax(0, 1fr) minmax(160px, 240px); gap: 24px; align-items: center; background: linear-gradient(135deg, rgba(255,255,255,0.96), rgba(237,245,239,0.96)); }
        .hero-badge { min-height: 140px; border-radius: 8px; background: repeating-linear-gradient(45deg, #0b6b5d, #0b6b5d 10px, #0d7868 10px, #0d7868 20px); color: #fff; display: grid; place-items: center; text-align: center; padding: 18px; }
        .hero-badge strong { font-size: 1.4rem; }
        .hero-badge span { display: block; font-family: Verdana, sans-serif; margin-top: 8px; }
        .catalog-grid, .report-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; }
        .product-card { padding: 18px; display: grid; gap: 12px; }
        .pill { display: inline-block; background: var(--soft); color: var(--brand-dark); padding: 5px 9px; border-radius: 999px; margin-bottom: 10px; }
        dl { display: grid; grid-template-columns: 80px 1fr; gap: 6px 10px; margin: 0; font-family: Verdana, sans-serif; font-size: 0.86rem; }
        dt { color: var(--muted); }
        dd { margin: 0; }
        .filters, .quick-order, .status-form { display: flex; flex-wrap: wrap; gap: 10px; align-items: end; }
        .quick-order { border-top: 1px solid var(--line); padding-top: 12px; }
        .quick-order strong { margin-right: auto; font-size: 1.3rem; }
        input, select { width: 100%; border: 1px solid #c8d1cc; border-radius: 6px; padding: 9px 10px; margin-top: 5px; background: #fff; color: var(--ink); }
        label { display: grid; gap: 2px; min-width: 160px; }
        .admin-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; align-items: end; }
        .admin-grid.compact { grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); }
        .span-all { grid-column: 1 / -1; }
        .stack { display: grid; gap: 14px; }
        .edit-card, .order-card { padding: 16px; }
        .edit-card.retired { opacity: 0.68; }
        .edit-heading { display: flex; gap: 10px; justify-content: space-between; align-items: baseline; margin-bottom: 12px; }
        .edit-heading span { color: var(--muted); font-family: Verdana, sans-serif; font-size: 0.84rem; }
        .actions { display: flex; gap: 8px; margin-top: 12px; align-items: center; }
        table { width: 100%; border-collapse: collapse; margin-top: 12px; background: #fff; }
        th, td { border-bottom: 1px solid var(--line); padding: 9px; text-align: left; vertical-align: top; }
        th { font-family: Verdana, sans-serif; font-size: 0.78rem; color: var(--muted); background: #f5f7f3; }
        .order-meta { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 12px; }
        .empty { padding: 20px; color: var(--muted); }
        footer { padding: 20px clamp(18px, 4vw, 52px); color: var(--muted); font-family: Verdana, sans-serif; font-size: 0.78rem; }
        @media (max-width: 760px) { header, .hero { grid-template-columns: 1fr; } .metrics { grid-template-columns: repeat(2, 1fr); } .quick-order strong { width: 100%; } }
        @media (max-width: 480px) { .metrics { grid-template-columns: 1fr; } nav a, button { width: 100%; text-align: center; } }
    </style>
</head>
<body>
    <header>
        <div>
            <p class="eyebrow">AdventureWorksLT on SQL Server</p>
            <h1>Legacy commerce operations</h1>
        </div>
        <div class="eyebrow">IIS + ASP.NET Web Forms + SQL auth</div>
    </header>
    <nav>
        <%= NavLink("catalog", "Storefront") %>
        <%= NavLink("products", "Products") %>
        <%= NavLink("customers", "Customers") %>
        <%= NavLink("orders", "Orders") %>
        <%= NavLink("reports", "Reports") %>
    </nav>
    <main>
        <% if (message.Length > 0) { %><div class="system ok"><%= H(message) %></div><% } %>
        <% if (error.Length > 0) { %><div class="system err">SQL error: <%= H(error) %></div><% } %>
        <%= RenderDashboard() %>
        <%= RenderCurrentView() %>
    </main>
    <footer>Host: <%= H(Environment.MachineName) %> &middot; Database: ArcBoxDemo &middot; Server time: <%= H(DateTime.UtcNow.ToString("u")) %></footer>
</body>
</html>
