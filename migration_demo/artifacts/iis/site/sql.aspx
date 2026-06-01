<%@ Page Language="C#" %>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        Response.Redirect("default.aspx?view=products", false);
        Context.ApplicationInstance.CompleteRequest();
    }
</script>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>SQL Server products</title>
    <meta http-equiv="refresh" content="0;url=default.aspx?view=products" />
</head>
<body>
    <p>SQL Server products are now managed in the <a href="default.aspx?view=products">AdventureWorks legacy storefront</a>.</p>
</body>
</html>