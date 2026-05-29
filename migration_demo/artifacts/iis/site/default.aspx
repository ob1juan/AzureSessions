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
    <h1>ArcBox Sample Web App</h1>
    <p>This site is hosted on the nested <strong>ArcBox-IIS</strong> Hyper-V VM and demonstrates connectivity to the other ArcBox data tier VMs.</p>
    <div class="card">
        <h3><a href="sql.aspx">SQL Server demo &rarr;</a></h3>
        <p>Reads from the <code>ArcBoxDemo</code> database running on <strong>ArcBox-SQL</strong>.</p>
    </div>
    <div class="card">
        <h3><a href="pg/pg.aspx">PostgreSQL demo &rarr;</a></h3>
        <p>Reads from the <code>arcboxdemo</code> database running on <strong>ArcBox-PG</strong> through the <code>/pg</code> virtual directory.</p>
    </div>
    <p><small>Hostname: <%= Environment.MachineName %> &middot; Server time: <%= DateTime.UtcNow.ToString("u") %></small></p>
</body>
</html>
