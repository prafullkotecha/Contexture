module Page.Bcc.Edit.Namespaces exposing
    ( Model
    , Msg
    , init
    , update
    , view
    )

import Api
import Array exposing (Array)
import Bootstrap.Accordion as Accordion
import Bootstrap.Button as Button
import Bootstrap.ButtonGroup as ButtonGroup
import Bootstrap.Card as Card
import Bootstrap.Card.Block as Block
import Bootstrap.Form as Form
import Bootstrap.Form.Fieldset as Fieldset
import Bootstrap.Form.Input as Input
import Bootstrap.Form.InputGroup as InputGroup
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Col as Col
import Bootstrap.Grid.Row as Row
import Bootstrap.ListGroup as ListGroup
import Bootstrap.Text as Text
import Bootstrap.Utilities.Display as Display
import Bootstrap.Utilities.Flex as Flex
import Bootstrap.Utilities.Spacing as Spacing
import BoundedContext.BoundedContextId exposing (BoundedContextId)
import BoundedContext.Namespace exposing (..)
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onSubmit)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as JP
import Json.Encode as Encode
import Page.Bcc.Edit.BusinessDecision exposing (Msg(..))
import RemoteData exposing (RemoteData)
import Url


type alias NewLabel =
    { name : String
    , value : String
    , isValid : Bool
    }


type alias CreateNamespace =
    { name : String
    , isValid : Bool
    , labels : Array NewLabel
    }


type alias NamespaceModel =
    { namespace : Namespace
    , addLabel : Maybe NewLabel
    }


type alias Model =
    { namespaces : RemoteData.WebData (List NamespaceModel)
    , accordionState : Accordion.State
    , newNamespace : Maybe CreateNamespace
    , configuration : Api.Configuration
    , boundedContextId : BoundedContextId
    }


initNamespace : Api.ApiResponse (List Namespace) -> RemoteData.WebData (List NamespaceModel)
initNamespace namespaceResult =
    namespaceResult
        |> RemoteData.fromResult
        |> RemoteData.map
            (\namespaces ->
                namespaces
                    |> List.map
                        (\n ->
                            { namespace = n, addLabel = Nothing }
                        )
            )


init : Api.Configuration -> BoundedContextId -> ( Model, Cmd Msg )
init config contextId =
    ( { namespaces = RemoteData.Loading
      , accordionState = Accordion.initialState
      , newNamespace = Nothing
      , configuration = config
      , boundedContextId = contextId
      }
    , loadNamespaces config contextId
    )


initNewLabel =
    { name = "", value = "", isValid = False }


initNewNamespace =
    { name = ""
    , isValid = False
    , labels = Array.empty
    }


type Msg
    = NamespacesLoaded (Api.ApiResponse (List Namespace))
    | AccordionMsg Accordion.State
    | StartAddingNamespace
    | ChangeNamespace String
    | AppendNewLabel
    | UpdateLabelName Int String
    | UpdateLabelValue Int String
    | RemoveLabel Int
    | AddNamespace CreateNamespace
    | NamespaceAdded (Api.ApiResponse (List Namespace))
    | CancelAddingNamespace
    | RemoveNamespace NamespaceId
    | NamespaceRemoved (Api.ApiResponse (List Namespace))
    | RemoveLabelFromNamespace NamespaceId LabelId
    | LabelRemoved (Api.ApiResponse (List Namespace))
    | AddingLabelToExistingNamespace NamespaceId
    | UpdateLabelNameForExistingNamespace NamespaceId String
    | UpdateLabelValueForExistingNamespace NamespaceId String
    | AddLabelToExistingNamespace NamespaceId NewLabel
    | CancelAddingLabelToExistingNamespace NamespaceId
    | LabelAddedToNamespace (Api.ApiResponse (List Namespace))


appendNewLabel namespace =
    { namespace | labels = namespace.labels |> Array.push initNewLabel }


updateLabel index updateLabelProperty namespace =
    let
        item =
            case namespace.labels |> Array.get index of
                Just element ->
                    updateLabelProperty element

                Nothing ->
                    updateLabelProperty initNewLabel
    in
    { namespace | labels = namespace.labels |> Array.set index item }


editingNamespace namespaceId updateNamespace namespaces =
    namespaces
        |> List.map
            (\n ->
                if n.namespace.id == namespaceId then
                    updateNamespace n

                else
                    n
            )


removeLabel : Int -> Array a -> Array a
removeLabel i a =
    let
        a1 =
            Array.slice 0 i a

        a2 =
            Array.slice (i + 1) (Array.length a) a
    in
    Array.append a1 a2


updateLabelName name label =
    { label
        | name = name
        , isValid = not <| String.isEmpty name
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NamespacesLoaded namespaces ->
            ( { model | namespaces = initNamespace namespaces }, Cmd.none )

        AccordionMsg state ->
            ( { model | accordionState = state }, Cmd.none )

        StartAddingNamespace ->
            ( { model | newNamespace = Just initNewNamespace }, Cmd.none )

        ChangeNamespace name ->
            ( { model
                | newNamespace =
                    model.newNamespace
                        |> Maybe.map (\namespace -> { namespace | name = name, isValid = not <| String.isEmpty name })
              }
            , Cmd.none
            )

        AppendNewLabel ->
            ( { model | newNamespace = model.newNamespace |> Maybe.map appendNewLabel }, Cmd.none )

        UpdateLabelName index name ->
            ( { model | newNamespace = model.newNamespace |> Maybe.map (updateLabel index (updateLabelName name)) }, Cmd.none )

        UpdateLabelValue index value ->
            ( { model | newNamespace = model.newNamespace |> Maybe.map (updateLabel index (\l -> { l | value = value })) }, Cmd.none )

        RemoveLabel index ->
            ( { model | newNamespace = model.newNamespace |> Maybe.map (\namespace -> { namespace | labels = namespace.labels |> removeLabel index }) }, Cmd.none )

        AddNamespace namespace ->
            ( model, addNamespace model.configuration model.boundedContextId namespace )

        NamespaceAdded namespaces ->
            ( { model
                | namespaces = initNamespace namespaces
                , newNamespace = Nothing
              }
            , Cmd.none
            )

        CancelAddingNamespace ->
            ( { model | newNamespace = Nothing }, Cmd.none )

        RemoveNamespace namespaceId ->
            ( model, removeNamespace model.configuration model.boundedContextId namespaceId )

        NamespaceRemoved namespaces ->
            ( { model | namespaces = initNamespace namespaces }, Cmd.none )

        RemoveLabelFromNamespace namespace label ->
            ( model, removeLabelFromNamespace model.configuration model.boundedContextId namespace label )

        LabelRemoved namespaces ->
            ( { model | namespaces = initNamespace namespaces }, Cmd.none )

        AddingLabelToExistingNamespace namespace ->
            ( { model | namespaces = model.namespaces |> RemoteData.map (editingNamespace namespace (\n -> { n | addLabel = Just initNewLabel })) }, Cmd.none )

        UpdateLabelNameForExistingNamespace namespace name ->
            ( { model | namespaces = model.namespaces |> RemoteData.map (editingNamespace namespace (\n -> { n | addLabel = n.addLabel |> Maybe.map (updateLabelName name) })) }, Cmd.none )

        UpdateLabelValueForExistingNamespace namespace value ->
            ( { model | namespaces = model.namespaces |> RemoteData.map (editingNamespace namespace (\n -> { n | addLabel = n.addLabel |> Maybe.map (\l -> { l | value = value }) })) }, Cmd.none )

        CancelAddingLabelToExistingNamespace namespace ->
            ( { model | namespaces = model.namespaces |> RemoteData.map (editingNamespace namespace (\n -> { n | addLabel = Nothing })) }, Cmd.none )

        AddLabelToExistingNamespace namespace newLabel ->
            ( model, addLabelToNamespace model.configuration model.boundedContextId namespace newLabel )

        LabelAddedToNamespace namespaces ->
            ( { model | namespaces = initNamespace namespaces }, Cmd.none )


viewAddLabelToExistingNamespace namespace model =
    Form.form [ onSubmit (AddLabelToExistingNamespace namespace model) ]
        [ Form.row []
            [ Form.col []
                [ Form.label [] [ text "Label" ]
                , Input.text
                    [ Input.placeholder "Label name"
                    , Input.value model.name
                    , if model.isValid then
                        Input.success

                      else
                        Input.danger
                    , Input.onInput (UpdateLabelNameForExistingNamespace namespace)
                    ]
                ]
            , Form.col []
                [ Form.label [] [ text "Value" ]
                , Input.text [ Input.placeholder "Label value", Input.value model.value, Input.onInput (UpdateLabelValueForExistingNamespace namespace) ]
                ]
            , Form.col [ Col.bottomSm ]
                [ ButtonGroup.buttonGroup []
                    [ ButtonGroup.button [ Button.secondary, Button.onClick (CancelAddingLabelToExistingNamespace namespace), Button.attrs [ type_ "button" ] ] [ text "Cancel" ]
                    , ButtonGroup.button
                        [ Button.primary, Button.disabled (not <| model.isValid) ]
                        [ text "Add Label" ]
                    ]
                ]
            ]
        ]


viewLabel namespace model =
    Block.custom <|
        Form.row []
            [ Form.colLabel [] [ text model.name ]
            , Form.col []
                [ Input.text [ Input.disabled True, Input.value model.value ] ]
            , Form.col [ Col.bottomSm ]
                [ Button.button [ Button.secondary, Button.onClick (RemoveLabelFromNamespace namespace model.id) ] [ text "X" ] ]
            ]


viewNamespace : NamespaceModel -> Accordion.Card Msg
viewNamespace { namespace, addLabel } =
    Accordion.card
        { id = namespace.id
        , options = []
        , header = Accordion.header [] <| Accordion.toggle [] [ text namespace.name ]
        , blocks =
            [ Accordion.block []
                (namespace.labels |> List.map (viewLabel namespace.id))
            , Accordion.block []
                (case addLabel of
                    Just label ->
                        [ Block.custom <| viewAddLabelToExistingNamespace namespace.id label ]

                    Nothing ->
                        []
                )
            , Accordion.block []
                [ Block.custom <|
                    Grid.row []
                        [ Grid.col []
                            [ Button.button
                                [ Button.primary, Button.onClick (AddingLabelToExistingNamespace namespace.id) ]
                                [ text "Add Label" ]
                            ]
                        , Grid.col [ Col.textAlign Text.alignSmRight ]
                            [ Button.button
                                [ Button.secondary, Button.onClick (RemoveNamespace namespace.id), Button.attrs [ class "align-sm-right" ] ]
                                [ text "Remove Namespace" ]
                            ]
                        ]
                ]
            ]
        }


view : Model -> Html Msg
view model =
    Card.config [ Card.attrs [ class "mb-3", class "shadow" ] ]
        |> Card.block []
            [ Block.titleH4 [] [ text "Namespaces" ]
            ]
        |> Card.block []
            (case model.namespaces of
                RemoteData.Success namespaces ->
                    Accordion.config AccordionMsg
                        |> Accordion.cards
                            (namespaces
                                |> List.map viewNamespace
                            )
                        |> Accordion.view model.accordionState
                        |> Block.custom
                        |> List.singleton

                e ->
                    [ e |> Debug.toString |> text |> Block.custom ]
            )
        |> Card.footer []
            [ case model.newNamespace of
                Nothing ->
                    Button.button
                        [ Button.primary
                        , Button.onClick StartAddingNamespace
                        ]
                        [ text "Add a new Namespace" ]

                Just newNamespace ->
                    viewNewNamespace newNamespace
            ]
        |> Card.view


viewAddLabel index model =
    Form.row []
        [ Form.col []
            [ Form.label [] [ text "Label" ]
            , Input.text
                [ Input.placeholder "Label name"
                , Input.value model.name
                , if model.isValid then
                    Input.success

                  else
                    Input.danger
                , Input.onInput (UpdateLabelName index)
                ]
            ]
        , Form.col []
            [ Form.label [] [ text "Value" ]
            , Input.text [ Input.placeholder "Label value", Input.value model.value, Input.onInput (UpdateLabelValue index) ]
            ]
        , Form.col [ Col.bottomSm ]
            [ Button.button [ Button.roleLink, Button.onClick (RemoveLabel index), Button.attrs [ type_ "button" ] ] [ text "X" ] ]
        ]


viewNewNamespace model =
    Form.form [ onSubmit (AddNamespace model) ]
        (Form.row []
            [ Form.col []
                [ Form.label [ for "namespace" ] [ text "Namespace" ]
                , Input.text
                    [ Input.id "namespace"
                    , Input.placeholder "The name of namespace containing the labels"
                    , Input.onInput ChangeNamespace
                    , if model.isValid then
                        Input.success

                      else
                        Input.danger
                    ]
                ]
            ]
            :: (model.labels |> Array.indexedMap viewAddLabel |> Array.toList)
            ++ [ Form.row []
                    [ Form.col []
                        [ Button.button [ Button.secondary, Button.onClick AppendNewLabel ] [ text "New Label" ] ]
                    , Form.col [ Col.smAuto ]
                        [ ButtonGroup.buttonGroup []
                            [ ButtonGroup.button [ Button.secondary, Button.onClick CancelAddingNamespace ] [ text "Cancel" ]
                            , ButtonGroup.button
                                [ Button.primary, Button.disabled <| not model.isValid, Button.attrs [ type_ "submit" ] ]
                                [ text "Add Namespace" ]
                            ]
                        ]
                    ]
               ]
        )


labelEncoder : NewLabel -> Encode.Value
labelEncoder model =
    Encode.object
        [ ( "name", Encode.string model.name )
        , ( "value", Encode.string model.value )
        ]


namespaceEncoder : CreateNamespace -> Encode.Value
namespaceEncoder model =
    Encode.object
        [ ( "name", Encode.string model.name )
        , ( "labels", model.labels |> Array.toList |> Encode.list labelEncoder )
        ]


loadNamespaces : Api.Configuration -> BoundedContextId -> Cmd Msg
loadNamespaces config boundedContextId =
    Http.get
        { url = Api.boundedContext boundedContextId |> Api.url config  |> (\b -> b ++ "/namespaces")
        , expect = Http.expectJson NamespacesLoaded (Decode.list namespaceDecoder)
        }


addNamespace : Api.Configuration -> BoundedContextId -> CreateNamespace -> Cmd Msg
addNamespace config boundedContextId namespace =
    Http.post
        { url = Api.boundedContext boundedContextId |> Api.url config  |> (\b -> b ++ "/namespaces")
        , body = Http.jsonBody <| namespaceEncoder namespace
        , expect = Http.expectJson NamespaceAdded (Decode.list namespaceDecoder)
        }


removeNamespace : Api.Configuration -> BoundedContextId -> NamespaceId -> Cmd Msg
removeNamespace config boundedContextId namespace =
    Http.request
        { method = "DELETE"
        , url = Api.boundedContext boundedContextId |> Api.url config  |> (\b -> b ++ "/namespaces/" ++ namespace)
        , body = Http.emptyBody
        , expect = Http.expectJson NamespaceRemoved (Decode.list namespaceDecoder)
        , timeout = Nothing
        , tracker = Nothing
        , headers = []
        }


removeLabelFromNamespace : Api.Configuration -> BoundedContextId -> NamespaceId -> LabelId -> Cmd Msg
removeLabelFromNamespace config boundedContextId namespace label =
    Http.request
        { method = "DELETE"
        , url = Api.boundedContext boundedContextId |> Api.url config  |> (\b -> b ++ "/namespaces/" ++ namespace ++ "/labels/" ++ label)
        , body = Http.emptyBody
        , expect = Http.expectJson LabelRemoved (Decode.list namespaceDecoder)
        , timeout = Nothing
        , tracker = Nothing
        , headers = []
        }


addLabelToNamespace : Api.Configuration -> BoundedContextId -> NamespaceId -> NewLabel -> Cmd Msg
addLabelToNamespace config boundedContextId namespace label =
    Http.post
        { url = Api.boundedContext boundedContextId |> Api.url config  |> (\b -> b ++ "/namespaces/" ++ namespace ++ "/labels")
        , body = Http.jsonBody <| labelEncoder label
        , expect = Http.expectJson LabelAddedToNamespace (Decode.list namespaceDecoder)
        }
