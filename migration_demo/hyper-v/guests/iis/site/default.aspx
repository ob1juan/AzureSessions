<%@ Page Language="C#" %>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>ArcBox Sample App</title>
    <style>
        body { font-family: Segoe UI, sans-serif; max-width: 760px; margin: 2em auto; color: #222; }
        h1 { color: #0078d4; }
        .card { border: 1px solid #ddd; border-radius: 6px; padding: 1em 1.5em; margin-bottom: 1em; }
        a { color: #0078d4; text-decoration: none; font-weight: 600; }
    </style>
</head>
<body>
    <h1>ArcBox SQL Legacy App</h1>
    <p>This ASP.NET Web Forms site is hosted on the nested <strong>ArcBox-SQL</strong> Hyper-V VM and uses SQL Server authentication against the local <code>ArcBoxDemo</code> database.</p>
    <div class="card">
        <h3><a href="sql.aspx">Manage products &rarr;</a></h3>
        <p>Create, read, update, and delete rows in <code>ArcBoxDemo.dbo.Products</code>.</p>
    </div>
    <p><small>Hostname: <%= Environment.MachineName %> &middot; Server time: <%= DateTime.UtcNow.ToString("u") %></small></p>
</body>
</html>
