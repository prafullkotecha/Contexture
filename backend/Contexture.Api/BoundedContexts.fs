namespace Contexture.Api

open Contexture.Api.Aggregates
open Contexture.Api.Database
open Contexture.Api.Domains
open Contexture.Api.Entities
open Contexture.Api.Aggregates.BoundedContext
open Contexture.Api.Infrastructure
open Contexture.Api.Infrastructure.Projections
open Microsoft.AspNetCore.Http
open FSharp.Control.Tasks

open Giraffe

module BoundedContexts =
    module Results =
        type BoundedContextResult =
            { Id: BoundedContextId
              ParentDomainId: DomainId
              Key: string option
              Name: string
              Description: string option
              Classification: StrategicClassification
              BusinessDecisions: BusinessDecision list
              UbiquitousLanguage: Map<string, UbiquitousLanguageTerm>
              Messages: Messages
              DomainRoles: DomainRole list
              TechnicalDescription: TechnicalDescription option
              Domain: Domain option
              Namespaces: Namespace list }

        let convertBoundedContextWithDomain (findDomain: DomainId -> Domain option) (findNamespaces: BoundedContextId -> Namespace list ) (boundedContext: BoundedContext) =
            { Id = boundedContext.Id
              ParentDomainId = boundedContext.DomainId
              Key = boundedContext.Key
              Name = boundedContext.Name
              Description = boundedContext.Description
              Classification = boundedContext.Classification
              BusinessDecisions = boundedContext.BusinessDecisions
              UbiquitousLanguage = boundedContext.UbiquitousLanguage
              Messages = boundedContext.Messages
              DomainRoles = boundedContext.DomainRoles
              TechnicalDescription = boundedContext.TechnicalDescription
              Domain = boundedContext.DomainId |> findDomain
              Namespaces = boundedContext.Id |> findNamespaces }

    module CommandEndpoints =
        open System
        open FileBasedCommandHandlers

        let clock = fun () -> DateTime.UtcNow

        let private updateAndReturnBoundedContext command =
            fun (next: HttpFunc) (ctx: HttpContext) ->
                task {
                    let database = ctx.GetService<EventStore>()

                    match BoundedContext.handle clock database command with
                    | Ok updatedContext ->
                        return! redirectTo false (sprintf "/api/boundedcontexts/%O" updatedContext) next ctx
                    | Error (DomainError EmptyName) ->
                        return! RequestErrors.BAD_REQUEST "Name must not be empty" next ctx
                    | Error e -> return! ServerErrors.INTERNAL_ERROR e next ctx
                }

        let technical contextId (command: UpdateTechnicalInformation) =
            updateAndReturnBoundedContext (UpdateTechnicalInformation(contextId, command))

        let rename contextId (command: RenameBoundedContext) =
            updateAndReturnBoundedContext (RenameBoundedContext(contextId, command))

        let key contextId (command: AssignKey) =
            updateAndReturnBoundedContext (AssignKey(contextId, command))

        let move contextId (command: MoveBoundedContextToDomain) =
            updateAndReturnBoundedContext (MoveBoundedContextToDomain(contextId, command))

        let reclassify contextId (command: ReclassifyBoundedContext) =
            updateAndReturnBoundedContext (ReclassifyBoundedContext(contextId, command))

        let description contextId (command: ChangeDescription) =
            updateAndReturnBoundedContext (ChangeDescription(contextId, command))

        let businessDecisions contextId (command: UpdateBusinessDecisions) =
            updateAndReturnBoundedContext (UpdateBusinessDecisions(contextId, command))

        let ubiquitousLanguage contextId (command: UpdateUbiquitousLanguage) =
            updateAndReturnBoundedContext (UpdateUbiquitousLanguage(contextId, command))

        let domainRoles contextId (command: UpdateDomainRoles) =
            updateAndReturnBoundedContext (UpdateDomainRoles(contextId, command))

        let messages contextId (command: UpdateMessages) =
            updateAndReturnBoundedContext (UpdateMessages(contextId, command))

        let removeAndReturnId contextId =
            fun (next: HttpFunc) (ctx: HttpContext) ->
                task {
                    let database = ctx.GetService<EventStore>()

                    match BoundedContext.handle clock database (RemoveBoundedContext contextId) with
                    | Ok id -> return! json id next ctx
                    | Error e -> return! ServerErrors.INTERNAL_ERROR e next ctx
                }

    module QueryEndpoints =
        open Contexture.Api.ReadModels
        let getBoundedContexts =
            fun (next: HttpFunc) (ctx: HttpContext) ->
                let eventStore = ctx.GetService<EventStore>()
                
                let namespacesOf = Namespace.allNamespacesByContext eventStore
                
                let boundedContexts =
                    eventStore
                    |> BoundedContext.allBoundedContexts
                    |> List.map (Results.convertBoundedContextWithDomain (Domain.buildDomain eventStore) namespacesOf)

                json boundedContexts next ctx

        let getBoundedContext contextId =
            fun (next: HttpFunc) (ctx: HttpContext) ->
                let eventStore = ctx.GetService<EventStore>()

                let namespacesOf = Namespace.allNamespacesByContext eventStore
                let result =
                    contextId
                    |> BoundedContext.buildBoundedContext eventStore
                    |> Option.map (Results.convertBoundedContextWithDomain (Domain.buildDomain eventStore) namespacesOf)
                    |> Option.map json
                    |> Option.defaultValue (RequestErrors.NOT_FOUND(sprintf "BoundedContext %O not found" contextId))

                result next ctx

    let routes: HttpHandler =
        subRouteCi
            "/boundedcontexts"
            (choose [ subRoutef "/%O" (fun contextId ->
                          (choose [ Namespaces.routes contextId
                                    GET >=> QueryEndpoints.getBoundedContext contextId
                                    POST
                                    >=> route "/technical"
                                    >=> bindJson (CommandEndpoints.technical contextId)
                                    POST
                                    >=> route "/rename"
                                    >=> bindJson (CommandEndpoints.rename contextId)
                                    POST
                                    >=> route "/key"
                                    >=> bindJson (CommandEndpoints.key contextId)
                                    POST
                                    >=> route "/move"
                                    >=> bindJson (CommandEndpoints.move contextId)
                                    POST
                                    >=> route "/reclassify"
                                    >=> bindJson (CommandEndpoints.reclassify contextId)
                                    POST
                                    >=> route "/description"
                                    >=> bindJson (CommandEndpoints.description contextId)
                                    POST
                                    >=> route "/businessDecisions"
                                    >=> bindJson (CommandEndpoints.businessDecisions contextId)
                                    POST
                                    >=> route "/ubiquitousLanguage"
                                    >=> bindJson (CommandEndpoints.ubiquitousLanguage contextId)
                                    POST
                                    >=> route "/domainRoles"
                                    >=> bindJson (CommandEndpoints.domainRoles contextId)
                                    POST
                                    >=> route "/messages"
                                    >=> bindJson (CommandEndpoints.messages contextId)
                                    DELETE >=> CommandEndpoints.removeAndReturnId contextId ]))
                      GET >=> QueryEndpoints.getBoundedContexts ])
