{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Redis.ManualCommands.FT where

import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

import Database.Redis.Core
import Database.Redis.ManualCommands (GeoUnit(..), SortOrder(..))
import Database.Redis.Protocol
import Database.Redis.Types

data FTOn
    = FTOnHash
    | FTOnJson
    deriving (Show, Eq)

instance RedisArg FTOn where
    encode FTOnHash = "HASH"
    encode FTOnJson = "JSON"

data FTIndexAllMode
    = FTIndexAllEnable
    | FTIndexAllDisable
    deriving (Show, Eq)

instance RedisArg FTIndexAllMode where
    encode FTIndexAllEnable = "ENABLE"
    encode FTIndexAllDisable = "DISABLE"

data FTFieldIdentifier
    = FTFieldName ByteString
    | FTFieldNameAs ByteString ByteString
    deriving (Show, Eq)

data FTSortable
    = FTSortable
    | FTSortableUnf
    deriving (Show, Eq)

data FTCommonFieldOpts = FTCommonFieldOpts
    { ftCommonFieldWithSuffixTrie :: Bool
    , ftCommonFieldIndexEmpty :: Bool
    , ftCommonFieldIndexMissing :: Bool
    , ftCommonFieldSortable :: Maybe FTSortable
    , ftCommonFieldNoIndex :: Bool
    } deriving (Show, Eq)

defaultFTCommonFieldOpts :: FTCommonFieldOpts
defaultFTCommonFieldOpts = FTCommonFieldOpts
    { ftCommonFieldWithSuffixTrie = False
    , ftCommonFieldIndexEmpty = False
    , ftCommonFieldIndexMissing = False
    , ftCommonFieldSortable = Nothing
    , ftCommonFieldNoIndex = False
    }

data FTTextFieldOpts = FTTextFieldOpts
    { ftTextFieldWeight :: Maybe Double
    , ftTextFieldNoStem :: Bool
    , ftTextFieldPhonetic :: Maybe ByteString
    , ftTextFieldCommonOpts :: FTCommonFieldOpts
    } deriving (Show, Eq)

defaultFTTextFieldOpts :: FTTextFieldOpts
defaultFTTextFieldOpts = FTTextFieldOpts
    { ftTextFieldWeight = Nothing
    , ftTextFieldNoStem = False
    , ftTextFieldPhonetic = Nothing
    , ftTextFieldCommonOpts = defaultFTCommonFieldOpts
    }

data FTTagFieldOpts = FTTagFieldOpts
    { ftTagFieldSeparator :: Maybe ByteString
    , ftTagFieldCaseSensitive :: Bool
    , ftTagFieldCommonOpts :: FTCommonFieldOpts
    } deriving (Show, Eq)

defaultFTTagFieldOpts :: FTTagFieldOpts
defaultFTTagFieldOpts = FTTagFieldOpts
    { ftTagFieldSeparator = Nothing
    , ftTagFieldCaseSensitive = False
    , ftTagFieldCommonOpts = defaultFTCommonFieldOpts
    }

data FTGeoShapeFieldOpts = FTGeoShapeFieldOpts
    { ftGeoShapeFieldCoordSystem :: Maybe ByteString
    , ftGeoShapeFieldCommonOpts :: FTCommonFieldOpts
    } deriving (Show, Eq)

defaultFTGeoShapeFieldOpts :: FTGeoShapeFieldOpts
defaultFTGeoShapeFieldOpts = FTGeoShapeFieldOpts
    { ftGeoShapeFieldCoordSystem = Nothing
    , ftGeoShapeFieldCommonOpts = defaultFTCommonFieldOpts
    }

data FTVectorFieldOpts = FTVectorFieldOpts
    { ftVectorFieldAlgorithm :: ByteString
    , ftVectorFieldAttributes :: NonEmpty (ByteString, ByteString)
    , ftVectorFieldCommonOpts :: FTCommonFieldOpts
    } deriving (Show, Eq)

data FTCreateField
    = FTCreateTextField FTFieldIdentifier FTTextFieldOpts
    | FTCreateTagField FTFieldIdentifier FTTagFieldOpts
    | FTCreateNumericField FTFieldIdentifier FTCommonFieldOpts
    | FTCreateGeoField FTFieldIdentifier FTCommonFieldOpts
    | FTCreateGeoShapeField FTFieldIdentifier FTGeoShapeFieldOpts
    | FTCreateVectorField FTFieldIdentifier FTVectorFieldOpts
    deriving (Show, Eq)

data FTCreateOpts = FTCreateOpts
    { ftCreateOn :: Maybe FTOn
    , ftCreateIndexAll :: Maybe FTIndexAllMode
    , ftCreatePrefixes :: [ByteString]
    , ftCreateFilter :: Maybe ByteString
    , ftCreateLanguage :: Maybe ByteString
    , ftCreateLanguageField :: Maybe ByteString
    , ftCreateScore :: Maybe Double
    , ftCreateScoreField :: Maybe ByteString
    , ftCreatePayloadField :: Maybe ByteString
    , ftCreateMaxTextFields :: Bool
    , ftCreateTemporarySeconds :: Maybe Double
    , ftCreateNoOffsets :: Bool
    , ftCreateNoHl :: Bool
    , ftCreateNoFields :: Bool
    , ftCreateNoFreqs :: Bool
    , ftCreateStopwords :: Maybe [ByteString]
    , ftCreateSkipInitialScan :: Bool
    } deriving (Show, Eq)

defaultFTCreateOpts :: FTCreateOpts
defaultFTCreateOpts = FTCreateOpts
    { ftCreateOn = Nothing
    , ftCreateIndexAll = Nothing
    , ftCreatePrefixes = []
    , ftCreateFilter = Nothing
    , ftCreateLanguage = Nothing
    , ftCreateLanguageField = Nothing
    , ftCreateScore = Nothing
    , ftCreateScoreField = Nothing
    , ftCreatePayloadField = Nothing
    , ftCreateMaxTextFields = False
    , ftCreateTemporarySeconds = Nothing
    , ftCreateNoOffsets = False
    , ftCreateNoHl = False
    , ftCreateNoFields = False
    , ftCreateNoFreqs = False
    , ftCreateStopwords = Nothing
    , ftCreateSkipInitialScan = False
    }

data FTAlterOpts = FTAlterOpts
    { ftAlterSkipInitialScan :: Bool
    } deriving (Show, Eq)

defaultFTAlterOpts :: FTAlterOpts
defaultFTAlterOpts = FTAlterOpts
    { ftAlterSkipInitialScan = False
    }

data FTExplainOpts = FTExplainOpts
    { ftExplainDialect :: Maybe Integer
    } deriving (Show, Eq)

defaultFTExplainOpts :: FTExplainOpts
defaultFTExplainOpts = FTExplainOpts
    { ftExplainDialect = Nothing
    }

data FTSearchContentMode
    = FTSearchReturnDocuments
    | FTSearchReturnIdsOnly
    deriving (Show, Eq)

data FTSearchScoreMode
    = FTSearchNoScores
    | FTSearchWithScores
    | FTSearchWithExplainScore
    deriving (Show, Eq)

data FTSearchPayloadMode
    = FTSearchNoPayloads
    | FTSearchWithPayloads
    deriving (Show, Eq)

data FTSearchSortKeysMode
    = FTSearchNoSortKeys
    | FTSearchWithSortKeys
    deriving (Show, Eq)

data FTReturnField
    = FTReturnField ByteString
    | FTReturnFieldAs ByteString ByteString
    deriving (Show, Eq)

data FTSummarizeOpts = FTSummarizeOpts
    { ftSummarizeFields :: [ByteString]
    , ftSummarizeFrags :: Maybe Integer
    , ftSummarizeLen :: Maybe Integer
    , ftSummarizeSeparator :: Maybe ByteString
    } deriving (Show, Eq)

defaultFTSummarizeOpts :: FTSummarizeOpts
defaultFTSummarizeOpts = FTSummarizeOpts
    { ftSummarizeFields = []
    , ftSummarizeFrags = Nothing
    , ftSummarizeLen = Nothing
    , ftSummarizeSeparator = Nothing
    }

data FTHighlightOpts = FTHighlightOpts
    { ftHighlightFields :: [ByteString]
    , ftHighlightTags :: Maybe (ByteString, ByteString)
    } deriving (Show, Eq)

defaultFTHighlightOpts :: FTHighlightOpts
defaultFTHighlightOpts = FTHighlightOpts
    { ftHighlightFields = []
    , ftHighlightTags = Nothing
    }

data FTNumericFilter = FTNumericFilter
    { ftNumericFilterField :: ByteString
    , ftNumericFilterMin :: Double
    , ftNumericFilterMax :: Double
    } deriving (Show, Eq)

data FTGeoFilter = FTGeoFilter
    { ftGeoFilterField :: ByteString
    , ftGeoFilterLongitude :: Double
    , ftGeoFilterLatitude :: Double
    , ftGeoFilterRadius :: Double
    , ftGeoFilterUnit :: GeoUnit
    } deriving (Show, Eq)

data FTSortBy = FTSortBy
    { ftSortByField :: ByteString
    , ftSortByOrder :: Maybe SortOrder
    } deriving (Show, Eq)

data FTSearchOpts = FTSearchOpts
    { ftSearchContentMode :: FTSearchContentMode
    , ftSearchVerbatim :: Bool
    , ftSearchNoStopWords :: Bool
    , ftSearchScoreMode :: FTSearchScoreMode
    , ftSearchPayloadMode :: FTSearchPayloadMode
    , ftSearchSortKeysMode :: FTSearchSortKeysMode
    , ftSearchNumericFilters :: [FTNumericFilter]
    , ftSearchGeoFilters :: [FTGeoFilter]
    , ftSearchInKeys :: [ByteString]
    , ftSearchInFields :: [ByteString]
    , ftSearchReturnFields :: [FTReturnField]
    , ftSearchSummarize :: Maybe FTSummarizeOpts
    , ftSearchHighlight :: Maybe FTHighlightOpts
    , ftSearchSlop :: Maybe Integer
    , ftSearchTimeout :: Maybe Integer
    , ftSearchInOrder :: Bool
    , ftSearchLanguage :: Maybe ByteString
    , ftSearchExpander :: Maybe ByteString
    , ftSearchScorer :: Maybe ByteString
    , ftSearchPayload :: Maybe ByteString
    , ftSearchSortBy :: Maybe FTSortBy
    , ftSearchLimit :: Maybe (Integer, Integer)
    , ftSearchParams :: [(ByteString, ByteString)]
    , ftSearchDialect :: Maybe Integer
    } deriving (Show, Eq)

defaultFTSearchOpts :: FTSearchOpts
defaultFTSearchOpts = FTSearchOpts
    { ftSearchContentMode = FTSearchReturnDocuments
    , ftSearchVerbatim = False
    , ftSearchNoStopWords = False
    , ftSearchScoreMode = FTSearchNoScores
    , ftSearchPayloadMode = FTSearchNoPayloads
    , ftSearchSortKeysMode = FTSearchNoSortKeys
    , ftSearchNumericFilters = []
    , ftSearchGeoFilters = []
    , ftSearchInKeys = []
    , ftSearchInFields = []
    , ftSearchReturnFields = []
    , ftSearchSummarize = Nothing
    , ftSearchHighlight = Nothing
    , ftSearchSlop = Nothing
    , ftSearchTimeout = Nothing
    , ftSearchInOrder = False
    , ftSearchLanguage = Nothing
    , ftSearchExpander = Nothing
    , ftSearchScorer = Nothing
    , ftSearchPayload = Nothing
    , ftSearchSortBy = Nothing
    , ftSearchLimit = Nothing
    , ftSearchParams = []
    , ftSearchDialect = Nothing
    }

data FTAggregateLoad
    = FTAggregateLoadAll
    | FTAggregateLoadFields (NonEmpty ByteString)
    deriving (Show, Eq)

data FTSortProperty = FTSortProperty
    { ftSortPropertyName :: ByteString
    , ftSortPropertyOrder :: Maybe SortOrder
    } deriving (Show, Eq)

data FTReduce = FTReduce
    { ftReduceFunction :: ByteString
    , ftReduceArgs :: [ByteString]
    , ftReduceAlias :: Maybe ByteString
    } deriving (Show, Eq)

data FTGroupBy = FTGroupBy
    { ftGroupByProperties :: NonEmpty ByteString
    , ftGroupByReducers :: [FTReduce]
    } deriving (Show, Eq)

data FTApply = FTApply
    { ftApplyExpression :: ByteString
    , ftApplyAlias :: Maybe ByteString
    } deriving (Show, Eq)

data FTCursorOpts = FTCursorOpts
    { ftCursorCount :: Maybe Integer
    , ftCursorMaxIdle :: Maybe Integer
    } deriving (Show, Eq)

defaultFTCursorOpts :: FTCursorOpts
defaultFTCursorOpts = FTCursorOpts
    { ftCursorCount = Nothing
    , ftCursorMaxIdle = Nothing
    }

data FTAggregateOpts = FTAggregateOpts
    { ftAggregateVerbatim :: Bool
    , ftAggregateLoad :: Maybe FTAggregateLoad
    , ftAggregateTimeout :: Maybe Integer
    , ftAggregateGroupBy :: [FTGroupBy]
    , ftAggregateSortBy :: Maybe (NonEmpty FTSortProperty, Maybe Integer)
    , ftAggregateApply :: [FTApply]
    , ftAggregateLimit :: Maybe (Integer, Integer)
    , ftAggregateFilter :: Maybe ByteString
    , ftAggregateCursor :: Maybe FTCursorOpts
    , ftAggregateParams :: [(ByteString, ByteString)]
    , ftAggregateDialect :: Maybe Integer
    } deriving (Show, Eq)

defaultFTAggregateOpts :: FTAggregateOpts
defaultFTAggregateOpts = FTAggregateOpts
    { ftAggregateVerbatim = False
    , ftAggregateLoad = Nothing
    , ftAggregateTimeout = Nothing
    , ftAggregateGroupBy = []
    , ftAggregateSortBy = Nothing
    , ftAggregateApply = []
    , ftAggregateLimit = Nothing
    , ftAggregateFilter = Nothing
    , ftAggregateCursor = Nothing
    , ftAggregateParams = []
    , ftAggregateDialect = Nothing
    }

data FTHybridSearchClause = FTHybridSearchClause
    { ftHybridSearchQuery :: ByteString
    , ftHybridSearchScorer :: Maybe ByteString
    , ftHybridSearchYieldScoreAs :: Maybe ByteString
    } deriving (Show, Eq)

data FTHybridVectorQuery
    = FTHybridKnn
        { ftHybridKnnCount :: Integer
        , ftHybridKnnK :: Integer
        , ftHybridKnnEfRuntime :: Maybe Integer
        , ftHybridKnnYieldScoreAs :: Maybe ByteString
        }
    | FTHybridRange
        { ftHybridRangeCount :: Integer
        , ftHybridRangeRadius :: Double
        , ftHybridRangeEpsilon :: Maybe Double
        , ftHybridRangeYieldScoreAs :: Maybe ByteString
        }
    deriving (Show, Eq)

data FTHybridVSimClause = FTHybridVSimClause
    { ftHybridVSimField :: ByteString
    , ftHybridVSimVector :: ByteString
    , ftHybridVSimQuery :: Maybe FTHybridVectorQuery
    , ftHybridVSimFilter :: Maybe ByteString
    } deriving (Show, Eq)

data FTHybridCombine
    = FTHybridCombineRRF
        { ftHybridRrfCount :: Integer
        , ftHybridRrfConstant :: Maybe Double
        , ftHybridRrfWindow :: Maybe Integer
        , ftHybridRrfYieldScoreAs :: Maybe ByteString
        }
    | FTHybridCombineLinear
        { ftHybridLinearCount :: Integer
        , ftHybridLinearAlphaBeta :: Maybe (Double, Double)
        , ftHybridLinearWindow :: Maybe Integer
        , ftHybridLinearYieldScoreAs :: Maybe ByteString
        }
    deriving (Show, Eq)

data FTHybridSort
    = FTHybridSortBy ByteString (Maybe SortOrder)
    | FTHybridNoSort
    deriving (Show, Eq)

data FTHybridLoad
    = FTHybridLoadFields (NonEmpty ByteString)
    | FTHybridLoadAll
    deriving (Show, Eq)

data FTHybridOpts = FTHybridOpts
    { ftHybridCombine :: Maybe FTHybridCombine
    , ftHybridLimit :: Maybe (Integer, Integer)
    , ftHybridSorting :: Maybe FTHybridSort
    , ftHybridParams :: [(ByteString, ByteString)]
    , ftHybridTimeout :: Maybe Integer
    , ftHybridFormat :: Maybe ByteString
    , ftHybridLoad :: Maybe FTHybridLoad
    , ftHybridGroupBy :: [FTGroupBy]
    , ftHybridApply :: [FTApply]
    , ftHybridFilter :: Maybe ByteString
    , ftHybridDialect :: Maybe Integer
    } deriving (Show, Eq)

defaultFTHybridOpts :: FTHybridOpts
defaultFTHybridOpts = FTHybridOpts
    { ftHybridCombine = Nothing
    , ftHybridLimit = Nothing
    , ftHybridSorting = Nothing
    , ftHybridParams = []
    , ftHybridTimeout = Nothing
    , ftHybridFormat = Nothing
    , ftHybridLoad = Nothing
    , ftHybridGroupBy = []
    , ftHybridApply = []
    , ftHybridFilter = Nothing
    , ftHybridDialect = Nothing
    }

data FTProfileQueryType
    = FTProfileSearch
    | FTProfileHybrid
    | FTProfileAggregate
    deriving (Show, Eq)

instance RedisArg FTProfileQueryType where
    encode FTProfileSearch = "SEARCH"
    encode FTProfileHybrid = "HYBRID"
    encode FTProfileAggregate = "AGGREGATE"

data FTProfileOpts = FTProfileOpts
    { ftProfileLimited :: Bool
    } deriving (Show, Eq)

defaultFTProfileOpts :: FTProfileOpts
defaultFTProfileOpts = FTProfileOpts
    { ftProfileLimited = False
    }

data FTSpellcheckTermsMode
    = FTSpellcheckInclude ByteString [ByteString]
    | FTSpellcheckExclude ByteString [ByteString]
    deriving (Show, Eq)

data FTSpellcheckOpts = FTSpellcheckOpts
    { ftSpellcheckDistance :: Maybe Integer
    , ftSpellcheckTermsMode :: Maybe FTSpellcheckTermsMode
    , ftSpellcheckDialect :: Maybe Integer
    } deriving (Show, Eq)

defaultFTSpellcheckOpts :: FTSpellcheckOpts
defaultFTSpellcheckOpts = FTSpellcheckOpts
    { ftSpellcheckDistance = Nothing
    , ftSpellcheckTermsMode = Nothing
    , ftSpellcheckDialect = Nothing
    }

data FTSugAddOpts
    = FTSugAddDefault
    | FTSugAddWithPayload ByteString
    | FTSugAddIncrement
    | FTSugAddIncrementWithPayload ByteString
    deriving (Show, Eq)

data FTCursorReadOpts = FTCursorReadOpts
    { ftCursorReadCount :: Maybe Integer
    } deriving (Show, Eq)

defaultFTCursorReadOpts :: FTCursorReadOpts
defaultFTCursorReadOpts = FTCursorReadOpts
    { ftCursorReadCount = Nothing
    }

countArgs :: [a] -> ByteString
countArgs = encode . (fromIntegral :: Int -> Integer) . length

fieldIdentifierToArgs :: FTFieldIdentifier -> [ByteString]
fieldIdentifierToArgs (FTFieldName name) = [name]
fieldIdentifierToArgs (FTFieldNameAs name alias) = [name, "AS", alias]

sortableToArgs :: FTSortable -> [ByteString]
sortableToArgs FTSortable = ["SORTABLE"]
sortableToArgs FTSortableUnf = ["SORTABLE", "UNF"]

commonFieldOptsToArgs :: FTCommonFieldOpts -> [ByteString]
commonFieldOptsToArgs FTCommonFieldOpts{..} =
    withSuffixTrieArg ++ indexEmptyArg ++ indexMissingArg ++ sortableArg ++ noIndexArg
  where
    withSuffixTrieArg = ["WITHSUFFIXTRIE" | ftCommonFieldWithSuffixTrie]
    indexEmptyArg = ["INDEXEMPTY" | ftCommonFieldIndexEmpty]
    indexMissingArg = ["INDEXMISSING" | ftCommonFieldIndexMissing]
    sortableArg = maybe [] sortableToArgs ftCommonFieldSortable
    noIndexArg = ["NOINDEX" | ftCommonFieldNoIndex]

createFieldToArgs :: FTCreateField -> [ByteString]
createFieldToArgs field =
    case field of
        FTCreateTextField identifier FTTextFieldOpts{..} ->
            fieldIdentifierToArgs identifier
                ++ ["TEXT"]
                ++ maybe [] (\weight -> ["WEIGHT", encode weight]) ftTextFieldWeight
                ++ ["NOSTEM" | ftTextFieldNoStem]
                ++ maybe [] (\matcher -> ["PHONETIC", matcher]) ftTextFieldPhonetic
                ++ commonFieldOptsToArgs ftTextFieldCommonOpts
        FTCreateTagField identifier FTTagFieldOpts{..} ->
            fieldIdentifierToArgs identifier
                ++ ["TAG"]
                ++ maybe [] (\separator -> ["SEPARATOR", separator]) ftTagFieldSeparator
                ++ ["CASESENSITIVE" | ftTagFieldCaseSensitive]
                ++ commonFieldOptsToArgs ftTagFieldCommonOpts
        FTCreateNumericField identifier opts ->
            fieldIdentifierToArgs identifier ++ ["NUMERIC"] ++ commonFieldOptsToArgs opts
        FTCreateGeoField identifier opts ->
            fieldIdentifierToArgs identifier ++ ["GEO"] ++ commonFieldOptsToArgs opts
        FTCreateGeoShapeField identifier FTGeoShapeFieldOpts{..} ->
            fieldIdentifierToArgs identifier
                ++ ["GEOSHAPE"]
                ++ maybe [] (\coordSystem -> ["COORD_SYSTEM", coordSystem]) ftGeoShapeFieldCoordSystem
                ++ commonFieldOptsToArgs ftGeoShapeFieldCommonOpts
        FTCreateVectorField identifier FTVectorFieldOpts{..} ->
            fieldIdentifierToArgs identifier
                ++ [ "VECTOR"
                   , ftVectorFieldAlgorithm
                   , countArgs (NE.toList ftVectorFieldAttributes)
                   ]
                ++ concatMap (\(name, value) -> [name, value]) (NE.toList ftVectorFieldAttributes)
                ++ commonFieldOptsToArgs ftVectorFieldCommonOpts

ftCreateOptsToArgs :: FTCreateOpts -> [ByteString]
ftCreateOptsToArgs FTCreateOpts{..} =
    onArg
        ++ indexAllArg
        ++ prefixesArg
        ++ filterArg
        ++ languageArg
        ++ languageFieldArg
        ++ scoreArg
        ++ scoreFieldArg
        ++ payloadFieldArg
        ++ maxTextFieldsArg
        ++ temporaryArg
        ++ noOffsetsArg
        ++ noHlArg
        ++ noFieldsArg
        ++ noFreqsArg
        ++ stopwordsArg
        ++ skipInitialScanArg
  where
    onArg = maybe [] (\dataType -> ["ON", encode dataType]) ftCreateOn
    indexAllArg = maybe [] (\mode -> ["INDEXALL", encode mode]) ftCreateIndexAll
    prefixesArg =
        if null ftCreatePrefixes
            then []
            else ["PREFIX", countArgs ftCreatePrefixes] ++ ftCreatePrefixes
    filterArg = maybe [] (\filterExpr -> ["FILTER", filterExpr]) ftCreateFilter
    languageArg = maybe [] (\lang -> ["LANGUAGE", lang]) ftCreateLanguage
    languageFieldArg = maybe [] (\field -> ["LANGUAGE_FIELD", field]) ftCreateLanguageField
    scoreArg = maybe [] (\score -> ["SCORE", encode score]) ftCreateScore
    scoreFieldArg = maybe [] (\field -> ["SCORE_FIELD", field]) ftCreateScoreField
    payloadFieldArg = maybe [] (\field -> ["PAYLOAD_FIELD", field]) ftCreatePayloadField
    maxTextFieldsArg = ["MAXTEXTFIELDS" | ftCreateMaxTextFields]
    temporaryArg = maybe [] (\seconds -> ["TEMPORARY", encode seconds]) ftCreateTemporarySeconds
    noOffsetsArg = ["NOOFFSETS" | ftCreateNoOffsets]
    noHlArg = ["NOHL" | ftCreateNoHl]
    noFieldsArg = ["NOFIELDS" | ftCreateNoFields]
    noFreqsArg = ["NOFREQS" | ftCreateNoFreqs]
    stopwordsArg = maybe [] (\words' -> ["STOPWORDS", countArgs words'] ++ words') ftCreateStopwords
    skipInitialScanArg = ["SKIPINITIALSCAN" | ftCreateSkipInitialScan]

ftAlterOptsToArgs :: FTAlterOpts -> [ByteString]
ftAlterOptsToArgs FTAlterOpts{..} =
    ["SKIPINITIALSCAN" | ftAlterSkipInitialScan]

ftExplainOptsToArgs :: FTExplainOpts -> [ByteString]
ftExplainOptsToArgs FTExplainOpts{..} =
    maybe [] (\dialect -> ["DIALECT", encode dialect]) ftExplainDialect

returnFieldToArgs :: FTReturnField -> [ByteString]
returnFieldToArgs (FTReturnField identifier) = [identifier]
returnFieldToArgs (FTReturnFieldAs identifier alias) = [identifier, "AS", alias]

summarizeOptsToArgs :: FTSummarizeOpts -> [ByteString]
summarizeOptsToArgs FTSummarizeOpts{..} =
    ["SUMMARIZE"]
        ++ fieldsArg
        ++ fragsArg
        ++ lenArg
        ++ separatorArg
  where
    fieldsArg =
        if null ftSummarizeFields
            then []
            else ["FIELDS", countArgs ftSummarizeFields] ++ ftSummarizeFields
    fragsArg = maybe [] (\frags -> ["FRAGS", encode frags]) ftSummarizeFrags
    lenArg = maybe [] (\len -> ["LEN", encode len]) ftSummarizeLen
    separatorArg = maybe [] (\separator -> ["SEPARATOR", separator]) ftSummarizeSeparator

highlightOptsToArgs :: FTHighlightOpts -> [ByteString]
highlightOptsToArgs FTHighlightOpts{..} =
    ["HIGHLIGHT"] ++ fieldsArg ++ tagsArg
  where
    fieldsArg =
        if null ftHighlightFields
            then []
            else ["FIELDS", countArgs ftHighlightFields] ++ ftHighlightFields
    tagsArg = maybe [] (\(openTag, closeTag) -> ["TAGS", openTag, closeTag]) ftHighlightTags

numericFilterToArgs :: FTNumericFilter -> [ByteString]
numericFilterToArgs FTNumericFilter{..} =
    [ "FILTER"
    , ftNumericFilterField
    , encode ftNumericFilterMin
    , encode ftNumericFilterMax
    ]

geoFilterToArgs :: FTGeoFilter -> [ByteString]
geoFilterToArgs FTGeoFilter{..} =
    [ "GEOFILTER"
    , ftGeoFilterField
    , encode ftGeoFilterLongitude
    , encode ftGeoFilterLatitude
    , encode ftGeoFilterRadius
    , encode ftGeoFilterUnit
    ]

sortByToArgs :: FTSortBy -> [ByteString]
sortByToArgs FTSortBy{..} =
    ["SORTBY", ftSortByField] ++ maybe [] (\order -> [encodeSortOrder order]) ftSortByOrder
  where
    encodeSortOrder Asc = "ASC"
    encodeSortOrder Desc = "DESC"

ftSearchOptsToArgs :: FTSearchOpts -> [ByteString]
ftSearchOptsToArgs FTSearchOpts{..} =
    contentArg
        ++ verbatimArg
        ++ noStopWordsArg
        ++ scoreArg
        ++ payloadsArg
        ++ sortKeysArg
        ++ concatMap numericFilterToArgs ftSearchNumericFilters
        ++ concatMap geoFilterToArgs ftSearchGeoFilters
        ++ inKeysArg
        ++ inFieldsArg
        ++ returnArg
        ++ maybe [] summarizeOptsToArgs ftSearchSummarize
        ++ maybe [] highlightOptsToArgs ftSearchHighlight
        ++ slopArg
        ++ timeoutArg
        ++ inOrderArg
        ++ languageArg
        ++ expanderArg
        ++ scorerArg
        ++ payloadArg
        ++ sortByArg
        ++ limitArg
        ++ paramsArg
        ++ dialectArg
  where
    contentArg = ["NOCONTENT" | ftSearchContentMode == FTSearchReturnIdsOnly]
    verbatimArg = ["VERBATIM" | ftSearchVerbatim]
    noStopWordsArg = ["NOSTOPWORDS" | ftSearchNoStopWords]
    scoreArg = case ftSearchScoreMode of
        FTSearchNoScores -> []
        FTSearchWithScores -> ["WITHSCORES"]
        FTSearchWithExplainScore -> ["WITHSCORES", "EXPLAINSCORE"]
    payloadsArg = ["WITHPAYLOADS" | ftSearchPayloadMode == FTSearchWithPayloads]
    sortKeysArg = ["WITHSORTKEYS" | ftSearchSortKeysMode == FTSearchWithSortKeys]
    inKeysArg =
        if null ftSearchInKeys
            then []
            else ["INKEYS", countArgs ftSearchInKeys] ++ ftSearchInKeys
    inFieldsArg =
        if null ftSearchInFields
            then []
            else ["INFIELDS", countArgs ftSearchInFields] ++ ftSearchInFields
    returnArg =
        if null ftSearchReturnFields
            then []
            else ["RETURN", countArgs ftSearchReturnFields] ++ concatMap returnFieldToArgs ftSearchReturnFields
    slopArg = maybe [] (\slop -> ["SLOP", encode slop]) ftSearchSlop
    timeoutArg = maybe [] (\timeout -> ["TIMEOUT", encode timeout]) ftSearchTimeout
    inOrderArg = ["INORDER" | ftSearchInOrder]
    languageArg = maybe [] (\language -> ["LANGUAGE", language]) ftSearchLanguage
    expanderArg = maybe [] (\expander -> ["EXPANDER", expander]) ftSearchExpander
    scorerArg = maybe [] (\scorer -> ["SCORER", scorer]) ftSearchScorer
    payloadArg = maybe [] (\payload -> ["PAYLOAD", payload]) ftSearchPayload
    sortByArg = maybe [] sortByToArgs ftSearchSortBy
    limitArg = maybe [] (\(offset, num) -> ["LIMIT", encode offset, encode num]) ftSearchLimit
    paramsArg =
        if null ftSearchParams
            then []
            else ["PARAMS", encode (fromIntegral (2 * length ftSearchParams) :: Integer)]
                ++ concatMap (\(name, value) -> [name, value]) ftSearchParams
    dialectArg = maybe [] (\dialect -> ["DIALECT", encode dialect]) ftSearchDialect

aggregateLoadToArgs :: FTAggregateLoad -> [ByteString]
aggregateLoadToArgs FTAggregateLoadAll = ["LOAD", "*"]
aggregateLoadToArgs (FTAggregateLoadFields fields) =
    ["LOAD", countArgs (NE.toList fields)] ++ NE.toList fields

sortPropertyToArgs :: FTSortProperty -> [ByteString]
sortPropertyToArgs FTSortProperty{..} =
    [ftSortPropertyName] ++ maybe [] (\order -> [encodeSortOrder order]) ftSortPropertyOrder
  where
    encodeSortOrder Asc = "ASC"
    encodeSortOrder Desc = "DESC"

reduceToArgs :: FTReduce -> [ByteString]
reduceToArgs FTReduce{..} =
    [ "REDUCE"
    , ftReduceFunction
    , encode (fromIntegral (length ftReduceArgs) :: Integer)
    ]
        ++ ftReduceArgs
        ++ maybe [] (\alias -> ["AS", alias]) ftReduceAlias

groupByToArgs :: FTGroupBy -> [ByteString]
groupByToArgs FTGroupBy{..} =
    [ "GROUPBY"
    , encode (fromIntegral (NE.length ftGroupByProperties) :: Integer)
    ]
        ++ NE.toList ftGroupByProperties
        ++ concatMap reduceToArgs ftGroupByReducers

applyToArgs :: FTApply -> [ByteString]
applyToArgs FTApply{..} =
    ["APPLY", ftApplyExpression] ++ maybe [] (\alias -> ["AS", alias]) ftApplyAlias

cursorOptsToArgs :: FTCursorOpts -> [ByteString]
cursorOptsToArgs FTCursorOpts{..} =
    ["WITHCURSOR"] ++ countArg ++ maxIdleArg
  where
    countArg = maybe [] (\count -> ["COUNT", encode count]) ftCursorCount
    maxIdleArg = maybe [] (\maxIdle -> ["MAXIDLE", encode maxIdle]) ftCursorMaxIdle

ftAggregateOptsToArgs :: FTAggregateOpts -> [ByteString]
ftAggregateOptsToArgs FTAggregateOpts{..} =
    verbatimArg
        ++ maybe [] aggregateLoadToArgs ftAggregateLoad
        ++ timeoutArg
        ++ concatMap groupByToArgs ftAggregateGroupBy
        ++ sortByArg
        ++ concatMap applyToArgs ftAggregateApply
        ++ limitArg
        ++ filterArg
        ++ maybe [] cursorOptsToArgs ftAggregateCursor
        ++ paramsArg
        ++ dialectArg
  where
    verbatimArg = ["VERBATIM" | ftAggregateVerbatim]
    timeoutArg = maybe [] (\timeout -> ["TIMEOUT", encode timeout]) ftAggregateTimeout
    sortByArg = maybe [] encodeSortBy ftAggregateSortBy
    encodeSortBy (properties, maxResults) =
        [ "SORTBY"
        , encode (fromIntegral (NE.length properties) :: Integer)
        ]
            ++ concatMap sortPropertyToArgs (NE.toList properties)
            ++ maybe [] (\max' -> ["MAX", encode max']) maxResults
    limitArg = maybe [] (\(offset, num) -> ["LIMIT", encode offset, encode num]) ftAggregateLimit
    filterArg = maybe [] (\expr -> ["FILTER", expr]) ftAggregateFilter
    paramsArg =
        if null ftAggregateParams
            then []
            else ["PARAMS", encode (fromIntegral (2 * length ftAggregateParams) :: Integer)]
                ++ concatMap (\(name, value) -> [name, value]) ftAggregateParams
    dialectArg = maybe [] (\dialect -> ["DIALECT", encode dialect]) ftAggregateDialect

hybridVectorQueryToArgs :: FTHybridVectorQuery -> [ByteString]
hybridVectorQueryToArgs FTHybridKnn{..} =
    [ "KNN"
    , encode ftHybridKnnCount
    , "K"
    , encode ftHybridKnnK
    ]
        ++ maybe [] (\efRuntime -> ["EF_RUNTIME", encode efRuntime]) ftHybridKnnEfRuntime
        ++ maybe [] (\name -> ["YIELD_SCORE_AS", name]) ftHybridKnnYieldScoreAs
hybridVectorQueryToArgs FTHybridRange{..} =
    [ "RANGE"
    , encode ftHybridRangeCount
    , "RADIUS"
    , encode ftHybridRangeRadius
    ]
        ++ maybe [] (\epsilon -> ["EPSILON", encode epsilon]) ftHybridRangeEpsilon
        ++ maybe [] (\name -> ["YIELD_SCORE_AS", name]) ftHybridRangeYieldScoreAs

hybridSearchClauseToArgs :: FTHybridSearchClause -> [ByteString]
hybridSearchClauseToArgs FTHybridSearchClause{..} =
    [ "SEARCH"
    , ftHybridSearchQuery
    ]
        ++ maybe [] (\scorer -> ["SCORER", scorer]) ftHybridSearchScorer
        ++ maybe [] (\name -> ["YIELD_SCORE_AS", name]) ftHybridSearchYieldScoreAs

hybridVSimClauseToArgs :: FTHybridVSimClause -> [ByteString]
hybridVSimClauseToArgs FTHybridVSimClause{..} =
    [ "VSIM"
    , ftHybridVSimField
    , ftHybridVSimVector
    ]
        ++ maybe [] hybridVectorQueryToArgs ftHybridVSimQuery
        ++ maybe [] (\expr -> ["FILTER", expr]) ftHybridVSimFilter

hybridCombineToArgs :: FTHybridCombine -> [ByteString]
hybridCombineToArgs FTHybridCombineRRF{..} =
    [ "COMBINE"
    , "RRF"
    , encode ftHybridRrfCount
    ]
        ++ maybe [] (\constant -> ["CONSTANT", encode constant]) ftHybridRrfConstant
        ++ maybe [] (\window -> ["WINDOW", encode window]) ftHybridRrfWindow
        ++ maybe [] (\name -> ["YIELD_SCORE_AS", name]) ftHybridRrfYieldScoreAs
hybridCombineToArgs FTHybridCombineLinear{..} =
    [ "COMBINE"
    , "LINEAR"
    , encode ftHybridLinearCount
    ]
        ++ maybe [] (\(alpha, beta) -> ["ALPHA", encode alpha, "BETA", encode beta]) ftHybridLinearAlphaBeta
        ++ maybe [] (\window -> ["WINDOW", encode window]) ftHybridLinearWindow
        ++ maybe [] (\name -> ["YIELD_SCORE_AS", name]) ftHybridLinearYieldScoreAs

hybridSortToArgs :: FTHybridSort -> [ByteString]
hybridSortToArgs FTHybridNoSort = ["NOSORT"]
hybridSortToArgs (FTHybridSortBy field order) =
    ["SORTBY", field] ++ maybe [] (\sortOrder -> [encodeSortOrder sortOrder]) order
  where
    encodeSortOrder Asc = "ASC"
    encodeSortOrder Desc = "DESC"

hybridLoadToArgs :: FTHybridLoad -> [ByteString]
hybridLoadToArgs FTHybridLoadAll = ["LOAD", "*"]
hybridLoadToArgs (FTHybridLoadFields fields) =
    ["LOAD", countArgs (NE.toList fields)] ++ NE.toList fields

ftHybridOptsToArgs :: FTHybridOpts -> [ByteString]
ftHybridOptsToArgs FTHybridOpts{..} =
    maybe [] hybridCombineToArgs ftHybridCombine
        ++ limitArg
        ++ maybe [] hybridSortToArgs ftHybridSorting
        ++ paramsArg
        ++ timeoutArg
        ++ formatArg
        ++ maybe [] hybridLoadToArgs ftHybridLoad
        ++ concatMap groupByToArgs ftHybridGroupBy
        ++ concatMap applyToArgs ftHybridApply
        ++ filterArg
        ++ dialectArg
  where
    limitArg = maybe [] (\(offset, num) -> ["LIMIT", encode offset, encode num]) ftHybridLimit
    paramsArg =
        if null ftHybridParams
            then []
            else ["PARAMS", encode (fromIntegral (2 * length ftHybridParams) :: Integer)]
                ++ concatMap (\(name, value) -> [name, value]) ftHybridParams
    timeoutArg = maybe [] (\timeout -> ["TIMEOUT", encode timeout]) ftHybridTimeout
    formatArg = maybe [] (\format -> ["FORMAT", format]) ftHybridFormat
    filterArg = maybe [] (\expr -> ["FILTER", expr]) ftHybridFilter
    dialectArg = maybe [] (\dialect -> ["DIALECT", encode dialect]) ftHybridDialect

ftProfileOptsToArgs :: FTProfileOpts -> [ByteString]
ftProfileOptsToArgs FTProfileOpts{..} =
    ["LIMITED" | ftProfileLimited]

spellcheckTermsModeToArgs :: FTSpellcheckTermsMode -> [ByteString]
spellcheckTermsModeToArgs termsMode =
    case termsMode of
        FTSpellcheckInclude dictionary terms ->
            ["TERMS", "INCLUDE", dictionary] ++ terms
        FTSpellcheckExclude dictionary terms ->
            ["TERMS", "EXCLUDE", dictionary] ++ terms

ftSpellcheckOptsToArgs :: FTSpellcheckOpts -> [ByteString]
ftSpellcheckOptsToArgs FTSpellcheckOpts{..} =
    distanceArg
        ++ maybe [] spellcheckTermsModeToArgs ftSpellcheckTermsMode
        ++ dialectArg
  where
    distanceArg = maybe [] (\distance -> ["DISTANCE", encode distance]) ftSpellcheckDistance
    dialectArg = maybe [] (\dialect -> ["DIALECT", encode dialect]) ftSpellcheckDialect

ftSugAddOptsToArgs :: FTSugAddOpts -> [ByteString]
ftSugAddOptsToArgs FTSugAddDefault = []
ftSugAddOptsToArgs (FTSugAddWithPayload payload) = ["PAYLOAD", payload]
ftSugAddOptsToArgs FTSugAddIncrement = ["INCR"]
ftSugAddOptsToArgs (FTSugAddIncrementWithPayload payload) = ["INCR", "PAYLOAD", payload]

ftCursorReadOptsToArgs :: FTCursorReadOpts -> [ByteString]
ftCursorReadOptsToArgs FTCursorReadOpts{..} =
    maybe [] (\count -> ["COUNT", encode count]) ftCursorReadCount

-- |Returns a list of all existing indexes (<https://redis.io/commands/ft._list>).
--
-- $O(1)$
--
-- Since RediSearch 2.0.0
ftList
    :: (RedisCtx m f)
    => m (f [ByteString])
ftList = sendRequest ["FT._LIST"]

-- |Run a search query on an index and perform aggregate transformations on the results (<https://redis.io/commands/ft.aggregate>).
--
-- The reply shape varies with options such as @WITHCURSOR@, so this wrapper returns the raw 'Reply'.
--
-- $O(1)$
--
-- Since RediSearch 1.1.0
ftAggregate
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Query string.
    -> m (f Reply)
ftAggregate index query = ftAggregateOpts index query defaultFTAggregateOpts

-- |Run a search query on an index and perform aggregate transformations on the results (<https://redis.io/commands/ft.aggregate>).
--
-- The reply shape varies with options such as @WITHCURSOR@, so this wrapper returns the raw 'Reply'.
--
-- $O(1)$
--
-- Since RediSearch 1.1.0
ftAggregateOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Query string.
    -> FTAggregateOpts -- ^ Aggregate options and transformation steps.
    -> m (f Reply)
ftAggregateOpts index query opts =
    sendRequest $ ["FT.AGGREGATE", index, query] ++ ftAggregateOptsToArgs opts

-- |Adds an alias to the index (<https://redis.io/commands/ft.aliasadd>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftAliasAdd
    :: (RedisCtx m f)
    => ByteString -- ^ Alias name.
    -> ByteString -- ^ Index name.
    -> m (f Status)
ftAliasAdd alias index = sendRequest ["FT.ALIASADD", alias, index]

-- |Deletes an alias from the index (<https://redis.io/commands/ft.aliasdel>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftAliasDel
    :: (RedisCtx m f)
    => ByteString -- ^ Alias name.
    -> m (f Status)
ftAliasDel alias = sendRequest ["FT.ALIASDEL", alias]

-- |Adds or updates an alias to the index (<https://redis.io/commands/ft.aliasupdate>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftAliasUpdate
    :: (RedisCtx m f)
    => ByteString -- ^ Alias name.
    -> ByteString -- ^ Index name.
    -> m (f Status)
ftAliasUpdate alias index = sendRequest ["FT.ALIASUPDATE", alias, index]

-- |Adds a new field to the index (<https://redis.io/commands/ft.alter>).
--
-- $O(N)$ where $N$ is the number of keys in the keyspace
--
-- Since RediSearch 1.0.0
ftAlter
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> FTCreateField -- ^ Field definition to append to the schema.
    -> m (f Status)
ftAlter index field = ftAlterOpts index field defaultFTAlterOpts

-- |Adds a new field to the index (<https://redis.io/commands/ft.alter>).
--
-- $O(N)$ where $N$ is the number of keys in the keyspace
--
-- Since RediSearch 1.0.0
ftAlterOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> FTCreateField -- ^ Field definition to append to the schema.
    -> FTAlterOpts -- ^ Alter options.
    -> m (f Status)
ftAlterOpts index field opts =
    sendRequest $ ["FT.ALTER", index] ++ ftAlterOptsToArgs opts ++ ["SCHEMA", "ADD"] ++ createFieldToArgs field

-- |Sets runtime configuration options (<https://redis.io/commands/ft.config-set>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftConfigSet
    :: (RedisCtx m f)
    => ByteString -- ^ Option name.
    -> ByteString -- ^ Option value.
    -> m (f Status)
ftConfigSet option value = sendRequest ["FT.CONFIG", "SET", option, value]

-- |Retrieves runtime configuration options (<https://redis.io/commands/ft.config-get>).
--
-- The server returns an option-dependent reply payload, so this wrapper returns the raw 'Reply'.
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftConfigGet
    :: (RedisCtx m f)
    => ByteString -- ^ Option name or pattern.
    -> m (f Reply)
ftConfigGet option = sendRequest ["FT.CONFIG", "GET", option]

-- |Creates an index with the given spec (<https://redis.io/commands/ft.create>).
--
-- $O(K)$ at creation where $K$ is the number of fields, $O(N)$ if scanning the keyspace is triggered, where $N$ is the number of keys in the keyspace
--
-- Since RediSearch 1.0.0
ftCreate
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> NonEmpty FTCreateField -- ^ Schema field definitions.
    -> m (f Status)
ftCreate index fields = ftCreateOpts index fields defaultFTCreateOpts

-- |Creates an index with the given spec (<https://redis.io/commands/ft.create>).
--
-- $O(K)$ at creation where $K$ is the number of fields, $O(N)$ if scanning the keyspace is triggered, where $N$ is the number of keys in the keyspace
--
-- Since RediSearch 1.0.0
ftCreateOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> NonEmpty FTCreateField -- ^ Schema field definitions.
    -> FTCreateOpts -- ^ Index creation options.
    -> m (f Status)
ftCreateOpts index fields opts =
    sendRequest $
        ["FT.CREATE", index]
            ++ ftCreateOptsToArgs opts
            ++ ["SCHEMA"]
            ++ concatMap createFieldToArgs (NE.toList fields)

-- |Deletes a cursor (<https://redis.io/commands/ft.cursor-del>).
--
-- $O(1)$
--
-- Since RediSearch 1.1.0
ftCursorDel
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> Integer -- ^ Cursor identifier.
    -> m (f Status)
ftCursorDel index cursorId = sendRequest ["FT.CURSOR", "DEL", index, encode cursorId]

-- |Reads from a cursor (<https://redis.io/commands/ft.cursor-read>).
--
-- The cursor batch payload is command-dependent, so this wrapper returns the raw 'Reply'.
--
-- $O(1)$
--
-- Since RediSearch 1.1.0
ftCursorRead
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> Integer -- ^ Cursor identifier.
    -> m (f Reply)
ftCursorRead index cursorId = ftCursorReadOpts index cursorId defaultFTCursorReadOpts

-- |Reads from a cursor (<https://redis.io/commands/ft.cursor-read>).
--
-- The cursor batch payload is command-dependent, so this wrapper returns the raw 'Reply'.
--
-- $O(1)$
--
-- Since RediSearch 1.1.0
ftCursorReadOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> Integer -- ^ Cursor identifier.
    -> FTCursorReadOpts -- ^ Cursor read options.
    -> m (f Reply)
ftCursorReadOpts index cursorId opts =
    sendRequest $ ["FT.CURSOR", "READ", index, encode cursorId] ++ ftCursorReadOptsToArgs opts

-- |Adds terms to a dictionary (<https://redis.io/commands/ft.dictadd>).
--
-- $O(1)$
--
-- Since RediSearch 1.4.0
ftDictAdd
    :: (RedisCtx m f)
    => ByteString -- ^ Dictionary name.
    -> NonEmpty ByteString -- ^ Terms to add.
    -> m (f Integer)
ftDictAdd dict terms = sendRequest $ ["FT.DICTADD", dict] ++ NE.toList terms

-- |Deletes terms from a dictionary (<https://redis.io/commands/ft.dictdel>).
--
-- $O(1)$
--
-- Since RediSearch 1.4.0
ftDictDel
    :: (RedisCtx m f)
    => ByteString -- ^ Dictionary name.
    -> NonEmpty ByteString -- ^ Terms to delete.
    -> m (f Integer)
ftDictDel dict terms = sendRequest $ ["FT.DICTDEL", dict] ++ NE.toList terms

-- |Deletes the index (<https://redis.io/commands/ft.dropindex>).
--
-- $O(1)$ or $O(N)$ if documents are deleted, where $N$ is the number of keys in the keyspace
--
-- Since RediSearch 2.0.0
ftDropIndex
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> m (f Status)
ftDropIndex index = sendRequest ["FT.DROPINDEX", index]

-- |Deletes the index (<https://redis.io/commands/ft.dropindex>).
--
-- This variant also deletes indexed documents.
--
-- $O(1)$ or $O(N)$ if documents are deleted, where $N$ is the number of keys in the keyspace
--
-- Since RediSearch 2.0.0
ftDropIndexDeleteDocs
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> m (f Status)
ftDropIndexDeleteDocs index = sendRequest ["FT.DROPINDEX", index, "DD"]

-- |Returns the execution plan for a complex query (<https://redis.io/commands/ft.explain>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftExplain
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Query string.
    -> m (f ByteString)
ftExplain index query = ftExplainOpts index query defaultFTExplainOpts

-- |Returns the execution plan for a complex query (<https://redis.io/commands/ft.explain>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftExplainOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Query string.
    -> FTExplainOpts -- ^ Explain options.
    -> m (f ByteString)
ftExplainOpts index query opts =
    sendRequest $ ["FT.EXPLAIN", index, query] ++ ftExplainOptsToArgs opts

-- |Performs hybrid search combining text search and vector similarity with configurable fusion methods (<https://redis.io/commands/ft.hybrid>).
--
-- The reply shape depends on requested projections and scoring options, so this wrapper returns the raw 'Reply'.
--
-- $O(N)$
--
-- Since Redis Open Source 8.4.0
ftHybrid
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> FTHybridSearchClause -- ^ Textual search clause.
    -> FTHybridVSimClause -- ^ Vector similarity clause.
    -> m (f Reply)
ftHybrid index searchClause vsimClause =
    ftHybridOpts index searchClause vsimClause defaultFTHybridOpts

-- |Performs hybrid search combining text search and vector similarity with configurable fusion methods (<https://redis.io/commands/ft.hybrid>).
--
-- The reply shape depends on requested projections and scoring options, so this wrapper returns the raw 'Reply'.
--
-- $O(N)$
--
-- Since Redis Open Source 8.4.0
ftHybridOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> FTHybridSearchClause -- ^ Textual search clause.
    -> FTHybridVSimClause -- ^ Vector similarity clause.
    -> FTHybridOpts -- ^ Hybrid query options.
    -> m (f Reply)
ftHybridOpts index searchClause vsimClause opts =
    sendRequest $
        ["FT.HYBRID", index]
            ++ hybridSearchClauseToArgs searchClause
            ++ hybridVSimClauseToArgs vsimClause
            ++ ftHybridOptsToArgs opts

-- |Returns information and statistics on the index (<https://redis.io/commands/ft.info>).
--
-- The response is a heterogeneous attribute map, so this wrapper returns the raw 'Reply'.
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftInfo
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> m (f Reply)
ftInfo index = sendRequest ["FT.INFO", index]

-- |Performs a `FT.SEARCH` or `FT.AGGREGATE` command and collects performance information (<https://redis.io/commands/ft.profile>).
--
-- The profiled reply depends on the wrapped query type, so this wrapper returns the raw 'Reply'.
--
-- $O(N)$
--
-- Since RediSearch 2.2.0
ftProfile
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> FTProfileQueryType -- ^ Wrapped query type.
    -> ByteString -- ^ Query payload for the wrapped command.
    -> m (f Reply)
ftProfile index queryType query =
    ftProfileOpts index queryType query defaultFTProfileOpts

-- |Performs a `FT.SEARCH` or `FT.AGGREGATE` command and collects performance information (<https://redis.io/commands/ft.profile>).
--
-- The profiled reply depends on the wrapped query type, so this wrapper returns the raw 'Reply'.
--
-- $O(N)$
--
-- Since RediSearch 2.2.0
ftProfileOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> FTProfileQueryType -- ^ Wrapped query type.
    -> ByteString -- ^ Query payload for the wrapped command.
    -> FTProfileOpts -- ^ Profiling options.
    -> m (f Reply)
ftProfileOpts index queryType query opts =
    sendRequest $
        ["FT.PROFILE", index, encode queryType]
            ++ ftProfileOptsToArgs opts
            ++ ["QUERY", query]

-- |Searches the index with a textual query, returning either documents or just ids (<https://redis.io/commands/ft.search>).
--
-- The reply shape depends on output flags such as @NOCONTENT@ and @WITHSCORES@, so this wrapper returns the raw 'Reply'.
--
-- $O(N)$
--
-- Since RediSearch 1.0.0
ftSearch
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Query string.
    -> m (f Reply)
ftSearch index query = ftSearchOpts index query defaultFTSearchOpts

-- |Searches the index with a textual query, returning either documents or just ids (<https://redis.io/commands/ft.search>).
--
-- The reply shape depends on output flags such as @NOCONTENT@ and @WITHSCORES@, so this wrapper returns the raw 'Reply'.
--
-- $O(N)$
--
-- Since RediSearch 1.0.0
ftSearchOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Query string.
    -> FTSearchOpts -- ^ Search options.
    -> m (f Reply)
ftSearchOpts index query opts =
    sendRequest $ ["FT.SEARCH", index, query] ++ ftSearchOptsToArgs opts

-- |Performs spelling correction on a query, returning suggestions for misspelled terms (<https://redis.io/commands/ft.spellcheck>).
--
-- The response contains nested suggestions, so this wrapper returns the raw 'Reply'.
--
-- $O(1)$
--
-- Since RediSearch 1.4.0
ftSpellcheck
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Query string.
    -> m (f Reply)
ftSpellcheck index query = ftSpellcheckOpts index query defaultFTSpellcheckOpts

-- |Performs spelling correction on a query, returning suggestions for misspelled terms (<https://redis.io/commands/ft.spellcheck>).
--
-- The response contains nested suggestions, so this wrapper returns the raw 'Reply'.
--
-- $O(1)$
--
-- Since RediSearch 1.4.0
ftSpellcheckOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Query string.
    -> FTSpellcheckOpts -- ^ Spellcheck options.
    -> m (f Reply)
ftSpellcheckOpts index query opts =
    sendRequest $ ["FT.SPELLCHECK", index, query] ++ ftSpellcheckOptsToArgs opts

-- |Adds a suggestion string to an auto-complete suggestion dictionary (<https://redis.io/commands/ft.sugadd>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftSugAdd
    :: (RedisCtx m f)
    => ByteString -- ^ Suggestion dictionary key.
    -> ByteString -- ^ Suggestion string.
    -> Double -- ^ Suggestion score.
    -> m (f Integer)
ftSugAdd key string score = ftSugAddOpts key string score FTSugAddDefault

-- |Adds a suggestion string to an auto-complete suggestion dictionary (<https://redis.io/commands/ft.sugadd>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftSugAddOpts
    :: (RedisCtx m f)
    => ByteString -- ^ Suggestion dictionary key.
    -> ByteString -- ^ Suggestion string.
    -> Double -- ^ Suggestion score.
    -> FTSugAddOpts -- ^ Suggestion insertion options.
    -> m (f Integer)
ftSugAddOpts key string score opts =
    sendRequest $ ["FT.SUGADD", key, string, encode score] ++ ftSugAddOptsToArgs opts

-- |Deletes a string from a suggestion index (<https://redis.io/commands/ft.sugdel>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftSugDel
    :: (RedisCtx m f)
    => ByteString -- ^ Suggestion dictionary key.
    -> ByteString -- ^ Suggestion string.
    -> m (f Integer)
ftSugDel key string = sendRequest ["FT.SUGDEL", key, string]

-- |Gets the size of an auto-complete suggestion dictionary (<https://redis.io/commands/ft.suglen>).
--
-- $O(1)$
--
-- Since RediSearch 1.0.0
ftSugLen
    :: (RedisCtx m f)
    => ByteString -- ^ Suggestion dictionary key.
    -> m (f Integer)
ftSugLen key = sendRequest ["FT.SUGLEN", key]

-- |Returns the distinct tags indexed in a Tag field (<https://redis.io/commands/ft.tagvals>).
--
-- $O(n)$ where $n$ is the number of distinct tags in the field
--
-- Since RediSearch 1.0.0
ftTagVals
    :: (RedisCtx m f)
    => ByteString -- ^ Index name.
    -> ByteString -- ^ Tag field name.
    -> m (f [ByteString])
ftTagVals index field = sendRequest ["FT.TAGVALS", index, field]
