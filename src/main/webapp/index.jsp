<%@page language="java" contentType="text/html" pageEncoding="UTF-8" %>
<%@page import="fasters.App"%>
<html>
<head>
    <title>Sample project.</title>
</head>
<body>
    <p align="center"><font color="#800000" size="6"><%="O PAI TA ON"%> </font></p>
    <h2 align="center">
      <% 
        App app = new App ();
        out.println(app.getSample()); 
      %>
    </h2>
</body>
</html>