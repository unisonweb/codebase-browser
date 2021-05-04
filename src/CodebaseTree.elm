module CodebaseTree exposing (Model, Msg, OutMsg(..), init, update, view)

import Api
import CodebaseTree.NamespaceListing as NamespaceListing
    exposing
        ( DefinitionListing(..)
        , NamespaceListing(..)
        , NamespaceListingContent
        )
import Definition.Category as Category
import Definition.Reference exposing (Reference(..))
import FullyQualifiedName as FQN exposing (FQN, unqualifiedName)
import FullyQualifiedNameSet as FQNSet exposing (FQNSet)
import HashQualified exposing (HashQualified(..))
import Html exposing (Html, a, div, h2, label, span, text)
import Html.Attributes exposing (class, id)
import Html.Events exposing (onClick)
import Http
import RemoteData exposing (RemoteData(..), WebData)
import UI
import UI.Icon as Icon



-- MODEL


type alias Model =
    { rootNamespaceListing : WebData NamespaceListing
    , expandedNamespaceListings : FQNSet
    }


init : ( Model, Cmd Msg )
init =
    let
        model =
            { rootNamespaceListing = Loading, expandedNamespaceListings = FQNSet.empty }
    in
    ( model, fetchRootNamespaceListing )



-- UPDATE


type Msg
    = ToggleExpandedNamespaceListing FQN
    | FetchSubNamespaceListingFinished FQN (Result Http.Error NamespaceListing)
    | FetchRootNamespaceListingFinished (Result Http.Error NamespaceListing)
    | OpenDefinitionListing Reference


type OutMsg
    = None
    | OpenDefinition Reference


update : Msg -> Model -> ( Model, Cmd Msg, OutMsg )
update msg model =
    case msg of
        ToggleExpandedNamespaceListing fqn ->
            let
                shouldExpand =
                    not (FQNSet.member fqn model.expandedNamespaceListings)

                newModel =
                    -- TODO: Update to Loading
                    { model
                        | expandedNamespaceListings =
                            FQNSet.toggle fqn
                                model.expandedNamespaceListings
                    }

                namespaceContentFetched =
                    model.rootNamespaceListing
                        |> RemoteData.map (\nl -> NamespaceListing.contentFetched nl fqn)
                        |> RemoteData.withDefault False

                cmd =
                    if shouldExpand && not namespaceContentFetched then
                        fetchSubNamespaceListing fqn

                    else
                        Cmd.none
            in
            ( newModel, cmd, None )

        FetchSubNamespaceListingFinished fetchedFqn result ->
            let
                replaceNamespaceListing ((NamespaceListing hash fqn _) as namespaceListing) =
                    if FQN.equals fetchedFqn fqn then
                        case result of
                            Ok (NamespaceListing _ _ content) ->
                                NamespaceListing hash fqn content

                            Err err ->
                                NamespaceListing hash fqn (Failure err)

                    else
                        namespaceListing

                nextNamespaceListing =
                    RemoteData.map (NamespaceListing.map replaceNamespaceListing) model.rootNamespaceListing
            in
            ( { model | rootNamespaceListing = nextNamespaceListing }, Cmd.none, None )

        FetchRootNamespaceListingFinished result ->
            case result of
                Ok (NamespaceListing hash fqn content) ->
                    ( { model | rootNamespaceListing = Success (NamespaceListing hash fqn content) }
                    , Cmd.none
                    , None
                    )

                Err err ->
                    ( { model | rootNamespaceListing = Failure err }, Cmd.none, None )

        OpenDefinitionListing ref ->
            ( model, Cmd.none, OpenDefinition ref )



-- EFFECTS


fetchRootNamespaceListing : Cmd Msg
fetchRootNamespaceListing =
    let
        rootFqn =
            FQN.fromString "."
    in
    Http.get
        { url = Api.list Nothing
        , expect = Http.expectJson FetchRootNamespaceListingFinished (NamespaceListing.decode rootFqn)
        }


fetchSubNamespaceListing : FQN -> Cmd Msg
fetchSubNamespaceListing fqn =
    Http.get
        { url = Api.list (Just (FQN.toString fqn))
        , expect = Http.expectJson (FetchSubNamespaceListingFinished fqn) (NamespaceListing.decode fqn)
        }



-- VIEW


viewListingRow : Maybe msg -> String -> String -> Icon.Icon -> Html msg
viewListingRow clickMsg label_ category icon =
    let
        containerClass =
            class ("node " ++ category)

        container =
            clickMsg
                |> Maybe.map (\msg -> a [ containerClass, onClick msg ])
                |> Maybe.withDefault (span [ containerClass ])
    in
    container
        [ Icon.view icon
        , label [] [ text label_ ]
        , span [ class "definition-category" ] [ text category ]
        ]


viewDefinitionListing : DefinitionListing -> Html Msg
viewDefinitionListing listing =
    let
        viewDefRow ref fqn =
            viewListingRow (Just (OpenDefinitionListing ref)) (unqualifiedName fqn)
    in
    case listing of
        TypeListing hash fqn category ->
            viewDefRow (TypeReference (HashOnly hash)) fqn (Category.name category) (Category.icon category)

        TermListing hash fqn category ->
            viewDefRow (TermReference (HashOnly hash)) fqn (Category.name category) (Category.icon category)

        DataConstructorListing hash fqn ->
            viewDefRow (DataConstructorReference (HashOnly hash)) fqn "constructor" Icon.DataConstructor

        AbilityConstructorListing hash fqn ->
            viewDefRow (AbilityConstructorReference (HashOnly hash)) fqn "constructor" Icon.AbilityConstructor

        PatchListing _ ->
            viewListingRow Nothing "Patch" "patch" Icon.Patch


viewLoadedNamespaceListingContent : FQNSet -> NamespaceListingContent -> Html Msg
viewLoadedNamespaceListingContent expandedNamespaceListings content =
    let
        namespaces =
            List.map (viewNamespaceListing expandedNamespaceListings) content.namespaces

        definitions =
            List.map viewDefinitionListing content.definitions
    in
    div [] (namespaces ++ definitions)


viewNamespaceListingContent : FQNSet -> WebData NamespaceListingContent -> Html Msg
viewNamespaceListingContent expandedNamespaceListings content =
    case content of
        Success loadedContent ->
            viewLoadedNamespaceListingContent expandedNamespaceListings loadedContent

        Failure err ->
            UI.errorMessage (Api.errorToString err)

        NotAsked ->
            UI.nothing

        Loading ->
            UI.loadingPlaceholder


viewNamespaceListing : FQNSet -> NamespaceListing -> Html Msg
viewNamespaceListing expandedNamespaceListings (NamespaceListing _ fqn content) =
    let
        ( caretIcon, namespaceContent ) =
            if FQNSet.member fqn expandedNamespaceListings then
                ( Icon.CaretDown
                , div [ class "namespace-content" ]
                    [ viewNamespaceListingContent
                        expandedNamespaceListings
                        content
                    ]
                )

            else
                ( Icon.CaretRight, UI.nothing )
    in
    div [ class "subtree" ]
        [ a
            [ class "node namespace"
            , onClick (ToggleExpandedNamespaceListing fqn)
            ]
            [ Icon.view caretIcon, label [] [ text (unqualifiedName fqn) ] ]
        , namespaceContent
        ]


view : Model -> Html Msg
view model =
    let
        listings =
            case model.rootNamespaceListing of
                Success (NamespaceListing _ _ content) ->
                    viewNamespaceListingContent
                        model.expandedNamespaceListings
                        content

                Failure err ->
                    UI.errorMessage (Api.errorToString err)

                NotAsked ->
                    UI.spinner

                Loading ->
                    UI.spinner
    in
    div [ id "all-namespaces" ]
        [ h2 [] [ text "All Namespaces" ]
        , div [ class "namespace-tree" ] [ listings ]
        ]