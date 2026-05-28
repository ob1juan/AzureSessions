<%@ Page Language="C#" %>
<%@ Import Namespace="System.Configuration" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>SQL Server demo &mdash; ArcBox</title>
    <style>
        body { font-family: Segoe UI, sans-serif; max-width: 760px; margin: 2em auto; color: #222; }
        h1 { color: #0078d4; }
        table { border-collapse: collapse; width: 100%; }
        th, td { padding: 0.4em 0.8em; border: 1px solid #ddd; text-align: left; }
        th { background: #f3f3f3; }
        .err { color: #a00; white-space: pre-wrap; }
    </style>
</head>
<body>
    <p><a href="default.aspx">&larr; Back</a></p>
    <h1>SQL Server demo</h1>
    <p>Querying <code>ArcBoxDemo.dbo.Products</code> on the <strong>ArcBox-SQL</strong> nested VM.</p>
<%
    string conn = ConfigurationManager.ConnectionStrings["ArcBoxSql"].ConnectionString;
    try {
        using (var c = new SqlConnection(conn))
        using (var cmd = new SqlCommand("SELECT Id, Name, Price, Stock FROM dbo.Products ORDER BY Id;", c)) {
            c.Open();
            using (var r = cmd.ExecuteReader()) {
                Response.Write("<table><tr><th>Id</th><th>Name</th><th>Price</th><th>Stock</th></tr>");
                while (r.Read()) {
                    Response.Write("<tr><td>" + r["Id"] + "</td><td>" + Server.HtmlEncode(r["Name"].ToString()) + "</td><td>" + ((decimal)r["Price"]).ToString("C") + "</td><td>" + r["Stock"] + "</td></tr>");
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
