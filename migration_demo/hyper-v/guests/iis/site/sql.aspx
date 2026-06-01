<%@ Page Language="C#" %>
<%@ Import Namespace="System.Configuration" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<script runat="server">
    string message = "";
    string error = "";

    protected void Page_Load(object sender, EventArgs e)
    {
        if (Request.HttpMethod == "POST")
        {
            try
            {
                SaveChanges();
            }
            catch (Exception ex)
            {
                error = ex.Message;
            }
        }
    }

    SqlConnection OpenConnection()
    {
        var connection = new SqlConnection(ConfigurationManager.ConnectionStrings["ArcBoxSql"].ConnectionString);
        connection.Open();
        return connection;
    }

    void SaveChanges()
    {
        string action = Request.Form["action"] ?? "";
        using (var connection = OpenConnection())
        using (var command = connection.CreateCommand())
        {
            if (action == "add" || action == "update")
            {
                string name = (Request.Form["name"] ?? "").Trim();
                decimal price;
                int stock;

                if (name.Length == 0 || !decimal.TryParse(Request.Form["price"], out price) || !int.TryParse(Request.Form["stock"], out stock))
                {
                    throw new Exception("Enter a name, numeric price, and numeric stock value.");
                }

                if (action == "add")
                {
                    command.CommandText = "INSERT INTO dbo.Products (Name, Price, Stock) VALUES (@name, @price, @stock);";
                }
                else
                {
                    int id;
                    if (!int.TryParse(Request.Form["id"], out id))
                    {
                        throw new Exception("Invalid product id.");
                    }
                    command.CommandText = "UPDATE dbo.Products SET Name = @name, Price = @price, Stock = @stock WHERE Id = @id;";
                    command.Parameters.Add("@id", SqlDbType.Int).Value = id;
                }

                command.Parameters.Add("@name", SqlDbType.NVarChar, 100).Value = name;
                command.Parameters.Add("@price", SqlDbType.Decimal).Value = price;
                command.Parameters.Add("@stock", SqlDbType.Int).Value = stock;
                command.ExecuteNonQuery();
                message = action == "add" ? "Product added." : "Product updated.";
            }
            else if (action == "delete")
            {
                int id;
                if (!int.TryParse(Request.Form["id"], out id))
                {
                    throw new Exception("Invalid product id.");
                }
                command.CommandText = "DELETE FROM dbo.Products WHERE Id = @id;";
                command.Parameters.Add("@id", SqlDbType.Int).Value = id;
                command.ExecuteNonQuery();
                message = "Product deleted.";
            }
        }
    }

    string H(object value)
    {
        return Server.HtmlEncode(Convert.ToString(value));
    }
</script>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>SQL Server CRUD - ArcBox</title>
    <style>
        body { font-family: Segoe UI, sans-serif; max-width: 760px; margin: 2em auto; color: #222; }
        h1 { color: #0078d4; }
        table { border-collapse: collapse; width: 100%; }
        th, td { padding: 0.4em 0.8em; border: 1px solid #ddd; text-align: left; }
        th { background: #f3f3f3; }
        input { width: 95%; padding: 0.35em; }
        button { padding: 0.4em 0.75em; margin-right: 0.25em; }
        .ok { color: #107c10; }
        .err { color: #a00; white-space: pre-wrap; }
    </style>
</head>
<body>
    <p><a href="default.aspx">&larr; Back</a></p>
    <h1>SQL Server products</h1>
    <p>Using SQL Server authentication against <code>ArcBoxDemo.dbo.Products</code> on <strong>ArcBox-SQL</strong>.</p>
    <% if (message.Length > 0) { %><p class="ok"><%= H(message) %></p><% } %>
    <% if (error.Length > 0) { %><p class="err">SQL error: <%= H(error) %></p><% } %>

    <h2>Add product</h2>
    <form method="post">
        <input type="hidden" name="action" value="add" />
        <p><label>Name<br /><input name="name" maxlength="100" required /></label></p>
        <p><label>Price<br /><input name="price" type="number" step="0.01" min="0" required /></label></p>
        <p><label>Stock<br /><input name="stock" type="number" min="0" required /></label></p>
        <button type="submit">Add</button>
    </form>

    <h2>Products</h2>
<%
    try {
        using (var c = OpenConnection())
        using (var cmd = new SqlCommand("SELECT Id, Name, Price, Stock FROM dbo.Products ORDER BY Id;", c)) {
            using (var r = cmd.ExecuteReader()) {
                Response.Write("<table><tr><th>Id</th><th>Name</th><th>Price</th><th>Stock</th><th>Actions</th></tr>");
                while (r.Read()) {
                    Response.Write("<tr><form method='post'>");
                    Response.Write("<td>" + r["Id"] + "<input type='hidden' name='id' value='" + r["Id"] + "' /></td>");
                    Response.Write("<td><input name='name' maxlength='100' value='" + H(r["Name"]) + "' /></td>");
                    Response.Write("<td><input name='price' type='number' step='0.01' min='0' value='" + ((decimal)r["Price"]).ToString("0.00") + "' /></td>");
                    Response.Write("<td><input name='stock' type='number' min='0' value='" + r["Stock"] + "' /></td>");
                    Response.Write("<td><button name='action' value='update' type='submit'>Save</button><button name='action' value='delete' type='submit'>Delete</button></td>");
                    Response.Write("</form></tr>");
                }
                Response.Write("</table>");
            }
        }
    } catch (Exception ex) {
        Response.Write("<p class='err'>SQL error: " + Server.HtmlEncode(ex.Message) + "</p>");
    }
%>
</body>
</html>
