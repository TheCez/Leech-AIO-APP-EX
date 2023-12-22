﻿using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using System.Text;

namespace RdtClient.Service.Middleware;

public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger _logger;

    public RequestLoggingMiddleware(RequestDelegate next, ILoggerFactory loggerFactory)
    {
        _next = next;
        _logger = loggerFactory.CreateLogger<RequestLoggingMiddleware>();
    }

    public async Task Invoke(HttpContext context)
    {
        if (!_logger.IsEnabled(LogLevel.Debug) || (!context.Request.Path.StartsWithSegments("/api/v2") && !context.Request.Path.StartsWithSegments("/api/torrents")))
        {
            await _next(context);

            return;
        }

        var requestLog = $"Method: {context.Request.Method}, Path: {context.Request.Path}";

        if (context.Request.QueryString.HasValue)
        {
            requestLog += $", QueryString: {context.Request.QueryString}";
        }

        if (context.Request.HasFormContentType && context.Request.Form.Any())
        {
            requestLog += $", Form: {String.Join(", ", context.Request.Form.Select(f => $"{f.Key}: {f.Value}"))}";
        }
        else if (context.Request.ContentType?.ToLower().Contains("application/json") == true)
        {
            var body = await ReadRequestBodyAsync(context.Request);
            requestLog += $", Body: {body}";
        }

        _logger.LogDebug(requestLog);

        await _next(context);
    }

    private static async Task<String> ReadRequestBodyAsync(HttpRequest request)
    {
        request.EnableBuffering();

        using var reader = new StreamReader(request.Body, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
        var body = await reader.ReadToEndAsync();

        request.Body.Position = 0;

        return body;
    }
}
