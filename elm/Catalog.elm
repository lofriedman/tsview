module Catalog exposing
    (Model, Msg, get, new, update, removeSeries)

import Common
import Dict exposing(Dict)
import Set exposing (Set)
import Http
import Json.Decode as Decode
import List.Extra exposing (unique)
import Url.Builder as UB


type alias RawSeries =
    Dict String (List (String, String))


type Error
    = Error String


type alias Model =
    { series : List String
    , seriesBySource : Dict String (Set String)
    , seriesByKind : Dict String (Set String)
    , error : Maybe Error
    }


type Msg
    = Received (Result String RawSeries)


-- catalog update

update msg model =
    case msg of
        Received (Ok x) ->
            new x

        Received (Err x) ->
            Model [] Dict.empty Dict.empty (Just (Error x))


-- catalog building

newseries : RawSeries -> List String
newseries raw =
    List.map Tuple.first (List.concat (Dict.values raw))


groupby : List (String, String)
        -> ((String, String) -> String)
        -> ((String, String) -> String)
        -> Dict String (Set String)
groupby list itemaccessor keyaccessor =
    let
        allkeys = unique (List.map keyaccessor list)
        filterItemsByKey items key =
            List.map itemaccessor (List.filter (\x -> (==) key (keyaccessor x)) items)
        makeDictEntry key =
            Tuple.pair key (Set.fromList (filterItemsByKey list key))
    in
        Dict.fromList (List.map makeDictEntry allkeys)


newkinds : RawSeries -> Dict String (Set String)
newkinds raw =
    groupby (List.concat (Dict.values raw)) Tuple.first Tuple.second


newsources raw =
    let
        namesbysource source =
            List.map Tuple.first (Maybe.withDefault [] (Dict.get source raw))
        makedictentry source =
            Tuple.pair source (Set.fromList (namesbysource source))
    in
         Dict.fromList (List.map makedictentry (Dict.keys raw))


new : RawSeries -> Model
new raw =
    let
        series = newseries raw
        seriesBySource = newsources raw
        seriesByKind = newkinds raw
    in
        Model series seriesBySource seriesByKind Nothing


removeSeries name catalog =
    let
        removeItem x xs = List.filter ((/=) x) xs
    in
        { catalog | series = removeItem name catalog.series }


-- catalog fetching

decodetuple =
    Decode.map2 Tuple.pair
        (Decode.index 0 Decode.string)
        (Decode.index 1 Decode.string)


get : String -> Cmd Msg
get urlprefix =
    Http.get
        { expect =
              (Common.expectJsonMessage Received)
              (Decode.dict (Decode.list decodetuple))
        , url =
            UB.crossOrigin urlprefix
                [ "api", "series", "catalog" ]
                []
        }
