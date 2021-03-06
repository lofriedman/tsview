module Plot exposing (main)

import Browser
import Common exposing (classes)
import Dict exposing (Dict, fromList, keys, values)
import Either exposing (Either)
import Html
import Html.Styled exposing (..)
import Html.Styled.Attributes as A
import Html.Styled.Events exposing (onClick)
import Http
import Catalog
import Json.Decode as Decode exposing (Decoder)
import KeywordSelector
import LruCache exposing (LruCache)
import Plotter exposing (scatterplot, plotargs, Series)
import SeriesSelector
import Tachyons.Classes as T
import Task exposing (Task)
import Time
import Url.Builder as UB


type alias Model =
    { urlPrefix : String
    , catalog: Catalog.Model
    , hasEditor : Bool
    , search : SeriesSelector.Model
    , selectedNamedSeries : List NamedSeries
    , activeSelection : Bool
    , cache : SeriesCache
    , error : Maybe Error
    }


type Error
    = SelectionError (List NamedError)
    | RenderError String
    | CatalogError Catalog.Error


type alias NamedSeries =
    ( String, Series )


type alias NamedError =
    ( String, String )


serieDecoder : Decoder Series
serieDecoder =
    Decode.dict Decode.float


type alias SeriesCache =
    LruCache String Series


type Msg
    = GotCatalog Catalog.Msg
    | ToggleSelection
    | ToggleItem String
    | SearchSeries String
    | MakeSearch
    | RenderPlot (Result (List String) ( SeriesCache, List NamedSeries, List NamedError ))
    | KindChange String Bool
    | SourceChange String Bool
    | ToggleMenu


plotFigure : List (Attribute msg) -> List (Html msg) -> Html msg
plotFigure =
    node "plot-figure"


fetchSeries :
    List String
    -> Model
    -> Task (List String) ( SeriesCache, List NamedSeries, List NamedError )
fetchSeries selectedNames model =
    let
        ( usedCache, cachedSeries ) =
            List.foldr
                (\name ( cache, xs ) ->
                     let
                         ( newCache, maybeSerie ) = LruCache.get name cache

                         x : Either String NamedSeries
                         x =
                             maybeSerie
                                |> Either.fromMaybe name
                                |> Either.map (Tuple.pair name)
                    in
                        ( newCache, x :: xs )
                )
            ( model.cache, [] )
            selectedNames

        missingNames = Either.lefts cachedSeries

        getSerie : String -> Task String Series
        getSerie serieName =
            Http.task
                { method = "GET"
                , url =
                    UB.crossOrigin
                        model.urlPrefix
                        [ "api", "series", "state" ]
                        [ UB.string "name" serieName ]
                , headers = []
                , body = Http.emptyBody
                , timeout = Nothing
                , resolver =
                    Http.stringResolver <|
                        Common.decodeJsonMessage serieDecoder
                }

        getMissingSeries : Task (List String) (List (Either String Series))
        getMissingSeries =
            Common.taskSequenceEither <| List.map getSerie missingNames

        getSeries : List NamedSeries -> List NamedSeries
        getSeries missing =
            let
                series =
                    List.append (Either.rights cachedSeries) missing
                        |> Dict.fromList
            in
                List.foldr
                    (\a b -> Common.maybe b (\x -> ( a, x ) :: b) (Dict.get a series))
                    []
                    selectedNames

        updateCache : List NamedSeries -> SeriesCache
        updateCache missing =
            List.foldl
                (\( name, serie ) cache -> LruCache.insert name serie cache)
                usedCache
                missing
    in
        getMissingSeries
            |> Task.onError (List.map Either.Left >> Task.succeed)
            |> Task.andThen
               (\missings ->
                    let
                        xs : List (Either NamedError NamedSeries)
                        xs =
                            List.map2
                            (\name x ->
                                 let
                                     addName = Tuple.pair name
                                 in
                                     Either.mapBoth addName addName x
                            )
                            missingNames
                            missings

                        missingSeries = Either.rights xs
                    in
                        Task.succeed
                            ( updateCache missingSeries
                            , getSeries missingSeries
                            , Either.lefts xs
                            )
               )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        removeItem x xs = List.filter ((/=) x) xs
        toggleItem x xs =
            if
                List.member x xs
            then
                removeItem x xs
            else
                x :: xs
        newModel x =
            ( x, Cmd.none )
        keywordMatch xm xs =
            if
                String.length xm < 2
            then
                []
            else
                KeywordSelector.select xm xs |> List.take 20
    in
        case msg of
            GotCatalog catmsg ->
                let
                    newcat = Catalog.update catmsg model.catalog
                    newsearch = SeriesSelector.fromcatalog model.search newcat
                in
                    ( { model
                          | catalog = newcat
                          , search = newsearch
                      }
                    , Task.attempt RenderPlot <| fetchSeries model.search.selected model
                    )

            ToggleMenu ->
                newModel { model | search = SeriesSelector.togglemenu model.search }

            KindChange kind checked ->
                let
                    newsearch = SeriesSelector.updatekinds
                                model.search
                                model.catalog
                                kind
                                checked
                in
                    newModel { model | search = newsearch }

            SourceChange source checked ->
                let
                    newsearch = SeriesSelector.updatesources
                                model.search
                                model.catalog
                                source
                                checked
                in
                    newModel { model | search = newsearch }

            ToggleSelection ->
                newModel { model | activeSelection = not model.activeSelection }

            ToggleItem x ->
                let
                    search = SeriesSelector.updateselected
                             model.search
                                 (toggleItem x model.search.selected)
                in
                    ( { model | search = search }
                    , Task.attempt RenderPlot <| fetchSeries search.selected model
                    )

            SearchSeries x ->
                let
                    search = SeriesSelector.updatesearch model.search x
                in
                    newModel { model | search = search }

            MakeSearch ->
                let
                    search = SeriesSelector.updatefound model.search
                             (keywordMatch
                                  model.search.search
                                  model.search.filteredseries)
                in
                    newModel { model | search = search }

            RenderPlot (Ok ( cache, namedSeries, namedErrors )) ->
                let
                    error =
                        case namedErrors of
                            [] ->
                                Nothing
                            xs ->
                                Just <| SelectionError xs
                in
                    newModel
                    { model
                        | cache = cache
                        , selectedNamedSeries = namedSeries
                        , error = error
                    }

            RenderPlot (Err xs) ->
                newModel
                { model
                    | error = Just <| RenderError <| String.join " " xs
                }


selectorConfig : SeriesSelector.SelectorConfig Msg
selectorConfig =
    { searchSelector =
        { action = Nothing
        , defaultText =
            text
                "Type some keywords in input bar for selecting time series"
        , toggleMsg = ToggleItem
        }
    , actionSelector =
        { action = Nothing
        , defaultText = text ""
        , toggleMsg = ToggleItem
        }
    , onInputMsg = SearchSeries
    , onMenuToggle = ToggleMenu
    , onKindChange = KindChange
    , onSourceChange = SourceChange
    , divAttrs = [ classes [ T.mb4 ] ]
    }


viewError : Error -> Html Msg
viewError error =
    let
        bold x =
            span [ classes [ T.b, T.mr4 ] ] [ text x ]
    in
        case error of
            RenderError x ->
                text x

            SelectionError namedErrors ->
                ul []
                    (List.map
                         (\( name, mess ) -> li [] [ bold name, text mess ])
                         namedErrors
                    )
            CatalogError x ->
                Catalog.viewError x



viewlinks cls hasEditor seriesName =
    div [ ]
        [ text (seriesName ++ " ")
        , a [A.href <| UB.relative [ "tsinfo" ] [ UB.string "name" seriesName]
            , A.target "_blank"
            , cls
            ]
              [ text <| "info" ]
        , text " "
        , a [ A.href <| UB.relative [ "tshistory", seriesName ] []
            , A.target "_blank"
            , cls
            ]
              [ text <| "history" ]
        , text " "
        , if hasEditor then
              a [ A.href <| UB.relative [ "tseditor/?name=" ++ seriesName ] []
                , A.target "_blank"
                , cls
                ]
              [ text <| "editor" ]
          else
              text ""
        ]


view : Model -> Html Msg
view model =
    let
        plotDiv = "plotly_div"
        args =
            let
                data =
                    List.map
                        (\( name, serie ) ->
                             scatterplot
                             name
                             (Dict.keys serie)
                             (Dict.values serie)
                             "lines"
                        )
                        model.selectedNamedSeries
            in
                plotargs plotDiv data

        selector =
            let
                cls = classes [ T.pb2, T.f4, T.fw6, T.db, T.navy, T.link, T.dim ]
                children =
                    [ a
                      [ cls, onClick ToggleSelection, A.title "click to toggle selector" ]
                      [ text "Series selection" ]
                    ]
            in
                form [ classes [ T.center, T.pt4, T.w_90 ] ]
                    (
                     if
                         model.activeSelection
                     then
                         List.append children
                             [ SeriesSelector.view
                                   model.search
                                   model.catalog
                                   selectorConfig
                             ]
                     else
                         children
                    )

        urls =
            let
                cls = classes [ T.link, T.blue, T.lh_title ]
                permalink =
                    let
                        url =
                            UB.relative
                                [ "tsview" ]
                                (List.map
                                     (\x -> UB.string "series" x)
                                     model.search.selected
                                )
                    in
                        a [ A.href url, cls ] [ text "Permalink" ]

                links =
                    List.map
                        (viewlinks cls model.hasEditor)
                        model.search.selected

            in
                ul [ classes [ T.list, T.mt3, T.mb0 ] ]
                    (List.map
                         (\x -> li [ classes [ T.pv2 ] ] [ x ])
                         (permalink :: links)
                    )
    in
        div []
            [ header [ classes [ T.bg_light_blue ] ] [ selector ]
            , div [ A.id plotDiv ] []
            , plotFigure [ A.attribute "args" args ] []
            , footer [] [ urls ]
            ]


main : Program
       { urlPrefix : String
       , selectedSeries : List String
       , hasEditor : Bool
       } Model Msg
main =
    let
        init flags =
            let
                prefix = flags.urlPrefix
                selected = flags.selectedSeries
            in
                ( Model
                      prefix
                      (Catalog.new Dict.empty)
                      flags.hasEditor
                      (SeriesSelector.new [] "" [] selected False [] [])
                      []
                      (List.isEmpty selected)
                      (LruCache.empty 100)
                      Nothing
            , Cmd.map GotCatalog (Catalog.get prefix 1)
            )

        sub model =
            if model.activeSelection then
                Time.every 1000 (always MakeSearch)

            else
                Sub.none
    in
        Browser.element
            { init = init
            , view = view >> toUnstyled
            , update = update
            , subscriptions = sub
            }
