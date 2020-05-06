module Search exposing (main)

import Browser
import Catalog as Cat
import Dict exposing (Dict)
import Html as H
import Html.Attributes as A
import Html.Events exposing (onInput, onClick)
import Html.Keyed as K
import Http
import Json.Decode as D
import Metadata as M
import Set exposing (Set)
import Url.Builder as UB
import Util as U


type alias Model =
    { baseurl : String
    -- base catalog elements
    , catalog : Cat.Model
    , metadata : Dict String M.MetaVal
    , formula : Dict String String
    -- filtered series
    , filtered : List String
    -- filter state
    , selectedkinds : List String
    , selectedsources : List String
    , filterbyname : Maybe String
    , filterbyformula : Maybe String
    , errors : List String
    }


type Msg
    = GotCatalog Cat.Msg
    | GotMeta (Result Http.Error String)
    | GotAllFormula (Result Http.Error String)
    | NameFilter String
    | FormulaFilter String
    | KindUpdated String
    | SourceUpdated String


getmeta baseurl =
    Http.get
        { expect =
              Http.expectString GotMeta
        , url =
            UB.crossOrigin baseurl
                [ "tssearch", "allmetadata" ] []
        }


decodemeta allmeta =
    let
        all = D.dict M.decodemetaval
    in
    D.decodeString all allmeta


getformula baseurl =
    Http.get
        { expect =
              Http.expectString GotAllFormula
        , url =
            UB.crossOrigin baseurl
                [ "tssearch", "allformula" ] []
        }


decodeformulae allformula =
    let
        all = D.dict D.string
    in
    D.decodeString all allformula


insert list item =
    List.append list [item]


remove list item =
    List.filter ((/=) item) list


-- filters

nullfilter model =
    { model | filtered = List.sort model.catalog.series }


namefilter model =
    case model.filterbyname of
        Nothing -> model
        Just item ->
            { model | filtered = List.filter (String.contains item) model.filtered }


formulafilter model =
    case model.filterbyformula of
        Nothing -> model
        Just item ->
            let
                formula name =
                    Maybe.withDefault "" <| Dict.get name model.formula
                informula name =
                    -- formula part -> name
                    String.contains item <| formula name
                series = List.filter informula model.filtered
            in
            { model | filtered = series }


catalogfilter series authority keys =
    if keys == Dict.keys authority then series else
    let
        seriesforkey key =
                Set.toList
                    <| Maybe.withDefault Set.empty
                    <| Dict.get key authority
        allseries =
            Set.fromList <| List.concat <| List.map seriesforkey keys
    in
    List.filter (\item -> (Set.member item allseries)) series


sourcefilter model =
    { model | filtered = catalogfilter
                         model.filtered
                         model.catalog.seriesBySource
                         model.selectedsources
    }


kindfilter model =
    { model | filtered = catalogfilter
                         model.filtered
                         model.catalog.seriesByKind
                         model.selectedkinds
    }


allfilters model =
    model |> nullfilter >> sourcefilter >> kindfilter >> namefilter >> formulafilter


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotCatalog catmsg ->
            let
                cat = Cat.update catmsg model.catalog
                newmodel = { model
                               | catalog = cat
                               , filtered = cat.series
                               , selectedkinds = Dict.keys cat.seriesByKind
                               , selectedsources = Dict.keys cat.seriesBySource
                           }
            in
            if List.isEmpty newmodel.catalog.series then
                U.nocmd newmodel
            else
                ( newmodel
                , Cmd.batch
                    [ getmeta model.baseurl
                    , getformula model.baseurl
                    ]
                )

        GotMeta (Ok rawmeta) ->
            case decodemeta rawmeta of
                Ok meta ->
                    U.nocmd { model | metadata = meta }
                Err err ->
                    U.nocmd <| U.adderror model <| D.errorToString err

        GotMeta (Err err) ->
            U.nocmd <| U.adderror model <| U.unwraperror err

        GotAllFormula (Ok rawformulae) ->
            case decodeformulae rawformulae of
                Ok formulae ->
                    U.nocmd { model | formula = formulae }
                Err err ->
                    U.nocmd <| U.adderror model <| D.errorToString err

        GotAllFormula (Err err) ->
            U.nocmd <| U.adderror model <| U.unwraperror err

        NameFilter value ->
            let
                filter = if value /= "" then Just value else Nothing
                newmodel = { model | filterbyname = filter }
            in
            U.nocmd <| allfilters newmodel

        FormulaFilter value ->
            let
                filter = if value /= "" then Just value else Nothing
                newmodel = { model | filterbyformula = filter }
            in
            U.nocmd <| allfilters newmodel

        KindUpdated kind ->
            let
                newkinds =
                    if List.member kind model.selectedkinds
                    then remove model.selectedkinds kind
                    else insert model.selectedkinds kind
                newmodel = { model | selectedkinds = List.sort newkinds }
            in
            U.nocmd <| allfilters newmodel

        SourceUpdated source ->
            let
                newsources =
                    if List.member source model.selectedsources
                    then remove model.selectedsources source
                    else insert model.selectedsources source
                newmodel = { model | selectedsources = newsources }
            in
            U.nocmd <| allfilters newmodel


viewnamefilter =
    H.input
    [ A.class "form-control"
    , A.placeholder "filter by name"
    , onInput NameFilter
    ] []


viewformulafilter =
    H.input
    [ A.class "form-control"
    , A.placeholder "filter on formula content"
    , onInput FormulaFilter
    ] []


viewkindfilter model =
    let
        kinds = Dict.keys model.catalog.seriesByKind
        checkbox kind =
            H.div [ A.class "form-check form-check-inline" ]
                [ H.input
                      [ A.attribute "type" "checkbox"
                      , A.class "form-check-input"
                      , A.value kind
                      , A.checked <| List.member kind model.selectedkinds
                      , onClick <| KindUpdated kind
                      ] []
                , H.label
                      [ A.class "form-check-label"
                      , A.for kind ]
                      [ H.text kind ]
                ]
    in
    H.div [] (List.map checkbox kinds)


viewsourcefilter model =
    let
        sources = Dict.keys model.catalog.seriesBySource
        checkbox source =
            H.div
                [ A.class "form-check form-check-inline" ]
                [ H.input
                      [ A.attribute "type" "checkbox"
                      , A.class "form-check-input"
                      , A.value source
                      , A.checked <| List.member source model.selectedsources
                      , onClick <| SourceUpdated source
                      ] []
                , H.label
                      [ A.class "form-check-label"
                      , A.for source ]
                      [ H.text source ]
                ]
    in
    H.div [] (List.map checkbox sources)


viewfilteredqty model =
    H.p
        []
        [ H.text ("Found "
                      ++ String.fromInt (List.length model.filtered)
                      ++ " items.")
        ]


viewfiltered model =
    let
        item elt =
            (elt, H.li []
                 [ H.a [ A.href (UB.crossOrigin
                                     model.baseurl
                                     [ "tsinfo" ]
                                     [ UB.string "name" elt ]
                                )
                       ] [ H.text elt ]
                 ])
    in
    K.node "ul" [] <| List.map item <| List.sort model.filtered


view : Model -> H.Html Msg
view model =
    H.div []
        [ H.h1 [] [ H.text "Series Catalog" ]
        , viewnamefilter
        , viewformulafilter
        , viewsourcefilter model
        , viewkindfilter model
        , viewfilteredqty model
        , viewfiltered model
        ]


type alias Input =
    { baseurl : String }


main : Program Input  Model Msg
main =
       let
           init input =
               ( Model
                     input.baseurl
                     ( Cat.Model
                         []
                         Dict.empty
                         Dict.empty
                         []
                     )
                     Dict.empty
                     Dict.empty
                     []
                     []
                     []
                     Nothing
                     Nothing
                     []
               ,
                   Cmd.map GotCatalog <| Cat.get input.baseurl 1
               )
           sub model = Sub.none
       in
           Browser.element
               { init = init
               , view = view
               , update = update
               , subscriptions = sub
               }
