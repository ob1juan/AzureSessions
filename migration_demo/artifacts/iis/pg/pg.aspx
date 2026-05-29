<%@ Page Language="C#" %>
<%@ Import Namespace="System.Configuration" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="Npgsql" %>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>PostgreSQL demo &mdash; ArcBox</title>
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
    <p><a href="/default.aspx">&larr; Back</a></p>
    <h1>PostgreSQL demo</h1>
    <p>Served from the <code>/pg</code> virtual directory. Querying <code>arcboxdemo.public.widgets</code> on the <strong>ArcBox-PG</strong> nested VM.</p>
<%
    string conn = ConfigurationManager.ConnectionStrings["ArcBoxPg"].ConnectionString;
    try {
        using (var c = new NpgsqlConnection(conn))
        using (var cmd = new NpgsqlCommand("SELECT id, name, qty FROM widgets ORDER BY id;", c)) {
            c.Open();
            using (var r = cmd.ExecuteReader()) {
                Response.Write("<table><tr><th>Id</th><th>Name</th><th>Qty</th></tr>");
                while (r.Read()) {
                    Response.Write("<tr><td>" + r["id"] + "</td><td>" + Server.HtmlEncode(r["name"].ToString()) + "</td><td>" + r["qty"] + "</td></tr>");
                }
                Response.Write("</table>");
            }
        }
    } catch (Exception ex) {
        Response.Write("<p class='err'>PostgreSQL error: " + Server.HtmlEncode(ex.Message) + "</p>");
    }
%>
</body>
</html>
