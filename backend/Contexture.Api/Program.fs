module Contexture.Api.App

open System
open System.IO
open Contexture.Api.Database
open Contexture.Api.Domains
open Giraffe
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Http
open Microsoft.AspNetCore.Cors.Infrastructure
open Microsoft.AspNetCore.Hosting
open Microsoft.Extensions.Configuration
open Microsoft.Extensions.Hosting
open Microsoft.Extensions.Logging
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Options

[<CLIMutable>]
type ContextureOptions = {
    DatabasePath : string
}

let allRoute =
     fun (next: HttpFunc) (ctx: HttpContext) ->
            let database = ctx.GetService<FileBased>()
            let document = database.Read

            let result =
                {| BoundedContexts = document.BoundedContexts.All |> List.map Results.convertBoundedContext
                   Domains = document.Domains.All |> List.map Results.convertDomain
                   Collaborations = document.Collaborations.All |}
            json result next ctx

let webApp hostFrontend =
    choose [
        subRoute "/api"
            (choose [
                Domains.routes
                BoundedContexts.routes
                Collaborations.routes
                GET >=> route "/all" >=> allRoute
            ])
        hostFrontend
        setStatusCode 404 >=> text "Not Found" ]

let frontendHostRoutes (env: IWebHostEnvironment) : HttpHandler =
    if env.IsDevelopment() then
        let skip : HttpFuncResult = System.Threading.Tasks.Task.FromResult None
        fun (next : HttpFunc) (ctx : HttpContext) ->
            skip
    else
        choose [
            route "/" >=> htmlFile "wwwroot/index.html"
            GET >=> htmlFile "wwwroot/index.html"
        ]

let errorHandler (ex : Exception) (logger : ILogger) =
    logger.LogError(ex, "An unhandled exception has occurred while executing the request.")
    clearResponse >=> setStatusCode 500 >=> text ex.Message

let configureCors (builder : CorsPolicyBuilder) =
    builder
        .AllowAnyOrigin()
        .AllowAnyMethod()
        .AllowAnyHeader()
        |> ignore

let configureApp (app : IApplicationBuilder) =
    let env = app.ApplicationServices.GetService<IWebHostEnvironment>()
    (match env.IsDevelopment() with
    | true  ->
        app.UseDeveloperExceptionPage()
    | false ->
        app.UseGiraffeErrorHandler(errorHandler))
        .UseCors(configureCors)
        .UseStaticFiles()
        .UseGiraffe(webApp (frontendHostRoutes env))
        
let configureJsonSerializer (services: IServiceCollection) =
    Database.Serialization.serializerOptions
    |> SystemTextJson.Serializer
    |> services.AddSingleton<Json.ISerializer>
    |> ignore


let configureServices (context: WebHostBuilderContext) (services : IServiceCollection) =
    services
        .AddOptions<ContextureOptions>()
        .Bind(context.Configuration)
        .Validate((fun options -> not (String.IsNullOrEmpty options.DatabasePath)), "A non-empty DatabasePath configuration is required")
        |> ignore
    services.AddSingleton<FileBased>(fun services ->
        let options = services.GetRequiredService<IOptions<ContextureOptions>>()
        FileBased.InitializeDatabase(options.Value.DatabasePath))
        |> ignore
    services.AddCors() |> ignore
    services.AddGiraffe() |> ignore
    services |> configureJsonSerializer

let configureLogging (builder : ILoggingBuilder) =
    builder.AddConsole()
           .AddDebug() |> ignore

[<EntryPoint>]
let main args =
    Host.CreateDefaultBuilder(args)
        .ConfigureWebHostDefaults(
            fun webHostBuilder ->
                webHostBuilder
                    .Configure(Action<IApplicationBuilder> configureApp)
                    .ConfigureServices(configureServices)
                    .ConfigureLogging(configureLogging)
                    |> ignore)
        .Build()
        .Run()
    0