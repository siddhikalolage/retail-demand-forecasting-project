param(
    [string]$ProjectRoot = (Join-Path $PSScriptRoot "retail_demand_command_center")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $json = $Value | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Get-ColumnField {
    param([string]$Table, [string]$Column)
    return [pscustomobject]@{
        Column = [pscustomobject]@{
            Expression = [pscustomobject]@{ SourceRef = [pscustomobject]@{ Entity = $Table } }
            Property = $Column
        }
    }
}

function Get-MeasureField {
    param([string]$Measure)
    return [pscustomobject]@{
        Measure = [pscustomobject]@{
            Expression = [pscustomobject]@{ SourceRef = [pscustomobject]@{ Entity = "_Measures" } }
            Property = $Measure
        }
    }
}

function Get-Projection {
    param([object]$Field, [string]$Reference, [string]$DisplayName = $null)
    $projection = [ordered]@{
        field = $Field
        queryRef = $Reference
        nativeQueryRef = ($Reference -split '\.')[-1]
    }
    if ($DisplayName) { $projection.displayName = $DisplayName }
    return [pscustomobject]$projection
}

function Get-Title {
    param([string]$Text, [int]$Size = 14)
    return @(
        [pscustomobject]@{
            properties = [pscustomobject]@{
                text = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "'$Text'" } } }
                fontSize = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "${Size}D" } } }
                fontColor = [pscustomobject]@{ solid = [pscustomobject]@{ color = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "'#E6EDF7'" } } } } }
            }
        }
    )
}

function New-Visual {
    param(
        [string]$Name, [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [int]$Z, [string]$VisualType, [object]$Visual
    )
    return [pscustomobject]@{
        '$schema' = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.9.0/schema.json"
        name = $Name
        position = [pscustomobject]@{ x = $X; y = $Y; z = $Z; height = $Height; width = $Width; tabOrder = $Z }
        visual = $Visual
        drillFilterOtherVisuals = $true
    }
}

function New-TextBox {
    param(
        [string]$Name, [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [int]$Z, [string]$Title, [string]$Subtitle = "", [int]$TitleSize = 26
    )
    $runs = @([pscustomobject]@{ value = $Title; textStyle = [pscustomobject]@{ fontWeight = "bold"; fontSize = "${TitleSize}pt"; color = "#F7FAFC" } })
    $paragraphs = @([pscustomobject]@{ textRuns = $runs })
    if ($Subtitle) {
        $paragraphs += [pscustomobject]@{ textRuns = @([pscustomobject]@{ value = $Subtitle; textStyle = [pscustomobject]@{ fontSize = "10pt"; color = "#A9B8CC" } }) }
    }
    $visual = [pscustomobject]@{
        visualType = "textbox"
        objects = [pscustomobject]@{
            general = @([pscustomobject]@{ properties = [pscustomobject]@{ paragraphs = $paragraphs } })
        }
    }
    return New-Visual $Name $X $Y $Width $Height $Z "textbox" $visual
}

function New-Card {
    param(
        [string]$Name, [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [int]$Z, [string]$Measure, [string]$Title
    )
    $visual = [pscustomobject]@{
        visualType = "cardVisual"
        query = [pscustomobject]@{
            queryState = [pscustomobject]@{
                Data = [pscustomobject]@{
					projections = @((Get-Projection (Get-MeasureField $Measure) "_Measures.$Measure" $Title))
                }
            }
        }
        visualContainerObjects = [pscustomobject]@{ title = (Get-Title $Title 12) }
        objects = [pscustomobject]@{
            categoryLabels = @([pscustomobject]@{ properties = [pscustomobject]@{ show = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "true" } } } } })
        }
    }
    return New-Visual $Name $X $Y $Width $Height $Z "cardVisual" $visual
}

function New-Slicer {
    param(
        [string]$Name, [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [int]$Z, [string]$Table, [string]$Column, [string]$Title
    )
    $reference = "$Table.$Column"
    $visual = [pscustomobject]@{
        visualType = "slicer"
        query = [pscustomobject]@{ queryState = [pscustomobject]@{ Values = [pscustomobject]@{ projections = @((Get-Projection (Get-ColumnField $Table $Column) $reference)) } } }
        objects = [pscustomobject]@{
            data = @([pscustomobject]@{ properties = [pscustomobject]@{ mode = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "'Dropdown'" } } } } })
            general = @([pscustomobject]@{ properties = [pscustomobject]@{ orientation = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "'1D'" } } } } })
            header = @([pscustomobject]@{ properties = [pscustomobject]@{ text = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "'$Title'" } } } } })
        }
        syncGroup = [pscustomobject]@{ groupName = "${Table}_${Column}"; fieldChanges = $true; filterChanges = $true }
    }
    return New-Visual $Name $X $Y $Width $Height $Z "slicer" $visual
}

function New-Chart {
    param(
        [string]$Name, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Z,
        [string]$Type, [string]$CategoryTable, [string]$CategoryColumn,
        [string[]]$Measures, [string]$Title
    )
    $categoryRef = "$CategoryTable.$CategoryColumn"
    $measureProjections = @()
    foreach ($measure in $Measures) {
        $measureProjections += Get-Projection (Get-MeasureField $measure) "_Measures.$measure" $measure
    }
    $visual = [pscustomobject]@{
        visualType = $Type
        query = [pscustomobject]@{
            queryState = [pscustomobject]@{
                Category = [pscustomobject]@{ projections = @((Get-Projection (Get-ColumnField $CategoryTable $CategoryColumn) $categoryRef)) }
                Y = [pscustomobject]@{ projections = $measureProjections }
            }
        }
        visualContainerObjects = [pscustomobject]@{ title = (Get-Title $Title) }
        objects = [pscustomobject]@{
            legend = @([pscustomobject]@{ properties = [pscustomobject]@{ show = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "true" } } } } })
            valueAxis = @([pscustomobject]@{ properties = [pscustomobject]@{ show = [pscustomobject]@{ expr = [pscustomobject]@{ Literal = [pscustomobject]@{ Value = "true" } } } } })
        }
    }
    return New-Visual $Name $X $Y $Width $Height $Z $Type $visual
}

function New-Matrix {
    param(
        [string]$Name, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Z,
        [string]$RowTable, [string]$RowColumn, [string[]]$Measures, [string]$Title
    )
    $measureProjections = @()
    foreach ($measure in $Measures) {
        $measureProjections += Get-Projection (Get-MeasureField $measure) "_Measures.$measure" $measure
    }
    $visual = [pscustomobject]@{
        visualType = "pivotTable"
        query = [pscustomobject]@{
            queryState = [pscustomobject]@{
                Rows = [pscustomobject]@{ projections = @((Get-Projection (Get-ColumnField $RowTable $RowColumn) "$RowTable.$RowColumn")) }
                Values = [pscustomobject]@{ projections = $measureProjections }
            }
        }
        visualContainerObjects = [pscustomobject]@{ title = (Get-Title $Title) }
    }
    return New-Visual $Name $X $Y $Width $Height $Z "pivotTable" $visual
}

function Write-Page {
    param([string]$Id, [string]$DisplayName, [object[]]$Visuals)
    $pageDir = Join-Path $pagesRoot $Id
    New-Item -ItemType Directory -Force -Path (Join-Path $pageDir "visuals") | Out-Null
    Write-JsonFile (Join-Path $pageDir "page.json") ([pscustomobject]@{
        '$schema' = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json"
        name = $Id; displayName = $DisplayName; displayOption = "FitToPage"; height = 810; width = 1440
    })
    foreach ($visual in $Visuals) {
        $visualPath = Join-Path $pageDir ("visuals\{0}\visual.json" -f $visual.name)
        Write-JsonFile $visualPath $visual
    }
}

$reportRoot = Join-Path $ProjectRoot "retail_demand_command_center.Report"
$pagesRoot = Join-Path $reportRoot "definition\pages"
New-Item -ItemType Directory -Force -Path $pagesRoot | Out-Null

Write-JsonFile (Join-Path $reportRoot "definition.pbir") ([pscustomobject]@{
    version = "4.0"; datasetReference = [pscustomobject]@{ byPath = [pscustomobject]@{ path = "../retail_demand_command_center.SemanticModel" } }
})

$theme = [pscustomobject]@{
    name = "Retail Command Center"
    dataColors = @("#42D3A8", "#66A8FF", "#FDBF5A", "#F47C9B", "#A78BFA", "#2DD4BF", "#F97316", "#94A3B8")
    background = "#0B1020"
    foreground = "#E6EDF7"
    tableAccent = "#42D3A8"
    visualStyles = [pscustomobject]@{
        '*' = [pscustomobject]@{
            '*' = [pscustomobject]@{
                background = @([pscustomobject]@{ show = $true; color = [pscustomobject]@{ solid = [pscustomobject]@{ color = "#121A2E" } }; transparency = 4 })
                title = @([pscustomobject]@{ show = $true; color = [pscustomobject]@{ solid = [pscustomobject]@{ color = "#E6EDF7" } }; fontSize = 13; fontFamily = "Segoe UI Semibold" })
                border = @([pscustomobject]@{ show = $false })
            }
        }
    }
}
Write-JsonFile (Join-Path $reportRoot "StaticResources\SharedResources\BuiltInThemes\RetailCommandCenter.json") $theme

Write-JsonFile (Join-Path $reportRoot "definition\report.json") ([pscustomobject]@{
    '$schema' = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.3.0/schema.json"
    themeCollection = [pscustomobject]@{
        customTheme = [pscustomobject]@{ name = "RetailCommandCenter"; type = "SharedResources" }
    }
    settings = [pscustomobject]@{ useEnhancedTooltips = $true; exportDataMode = "AllowSummarized"; filterPaneHiddenInEditMode = $true }
    resourcePackages = @([pscustomobject]@{ name = "SharedResources"; type = "SharedResources"; items = @([pscustomobject]@{ name = "RetailCommandCenter"; path = "BuiltInThemes/RetailCommandCenter.json"; type = "CustomTheme" }) })
})
Write-JsonFile (Join-Path $reportRoot "definition\version.json") ([pscustomobject]@{ '$schema' = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/versionMetadata/1.0.0/schema.json"; version = "2.0.0" })

$overview = "1f3070f1b2c3d4e5f607"
$demand = "2f3070f1b2c3d4e5f607"
$price = "3f3070f1b2c3d4e5f607"
$forecast = "4f3070f1b2c3d4e5f607"
$action = "5f3070f1b2c3d4e5f607"

Write-Page $overview "Executive Pulse" @(
    (New-TextBox "10000000000000000001" 30 18 900 60 10 "Retail Demand Command Center" "Executive pulse | demand, margin, forecast and actions in one decision workspace"),
    (New-Slicer "10000000000000000002" 940 24 220 46 11 "DIM_CALENDAR" "CALENDAR_DATE" "Period"),
    (New-Slicer "10000000000000000003" 1175 24 120 46 12 "DIM_ITEM" "CAT_ID" "Category"),
    (New-Slicer "10000000000000000004" 1310 24 100 46 13 "DIM_STORE" "STATE_ID" "State"),
    (New-Card "10000000000000000005" 30 100 210 105 20 "Total Revenue" "Revenue"),
    (New-Card "10000000000000000006" 255 100 210 105 21 "Revenue Growth %" "Revenue Growth"),
    (New-Card "10000000000000000007" 480 100 210 105 22 "Total Units" "Units Sold"),
    (New-Card "10000000000000000008" 705 100 210 105 23 "Avg Selling Price" "Avg Selling Price"),
    (New-Card "10000000000000000009" 930 100 210 105 24 "Active Items" "Active SKUs"),
    (New-Card "1000000000000000000a" 1155 100 255 105 25 "Forecast Risk Status" "Forecast Risk"),
    (New-Chart "1000000000000000000b" 30 230 860 310 30 "lineChart" "DIM_CALENDAR" "CALENDAR_DATE" @("Total Revenue", "Revenue 30D Average") "Revenue trajectory and 30-day baseline"),
    (New-Chart "1000000000000000000c" 915 230 495 310 31 "clusteredBarChart" "DIM_ITEM" "CAT_ID" @("Total Revenue") "Revenue concentration by category"),
    (New-TextBox "1000000000000000000d" 30 570 650 165 40 "Decision signal" "Read the trend against its 30-day baseline. Sustained downside movement calls for a category and store drill-down; isolated spikes should be checked against calendar events before changing inventory." 16),
    (New-TextBox "1000000000000000000e" 705 570 705 165 41 "Risk guardrail" "Forecast risk is derived from the 95% interval width. Use it to scale safety stock and review cadence, not as a measure of future forecast accuracy." 16)
)

Write-Page $demand "Demand Intelligence" @(
    (New-TextBox "20000000000000000001" 30 18 900 60 10 "Demand Intelligence" "Where demand is concentrated, accelerating, and exposed to concentration risk"),
    (New-Slicer "20000000000000000002" 940 24 220 46 11 "DIM_CALENDAR" "CALENDAR_DATE" "Period"),
    (New-Slicer "20000000000000000003" 1175 24 120 46 12 "DIM_ITEM" "CAT_ID" "Category"),
    (New-Slicer "20000000000000000004" 1310 24 100 46 13 "DIM_STORE" "STATE_ID" "State"),
    (New-Card "20000000000000000005" 30 100 225 105 20 "Revenue Share %" "Selected Revenue Share"),
    (New-Card "20000000000000000006" 270 100 225 105 21 "Units vs 30D Average %" "Demand vs Baseline"),
    (New-Card "20000000000000000007" 510 100 225 105 22 "Active Stores" "Active Stores"),
    (New-Card "20000000000000000008" 750 100 300 105 23 "Demand Signal" "Demand Signal"),
    (New-Card "20000000000000000009" 1065 100 345 105 24 "Recommended Action" "Recommended Action"),
    (New-Chart "2000000000000000000a" 30 230 660 300 30 "clusteredBarChart" "DIM_ITEM" "DEPT_ID" @("Total Revenue") "Department revenue ranking"),
    (New-Chart "2000000000000000000b" 715 230 695 300 31 "lineChart" "DIM_CALENDAR" "CALENDAR_DATE" @("Total Units") "Demand pattern over time"),
    (New-Matrix "2000000000000000000c" 30 560 900 190 40 "DIM_STORE" "STORE_ID" @("Total Revenue", "Total Units", "Avg Selling Price") "Store performance scan"),
    (New-TextBox "2000000000000000000d" 955 560 455 190 41 "Action playbook" "High concentration: protect availability for dominant departments. Below-baseline demand: inspect price, calendar and local-store signals before discounting. Use the store scan to direct field follow-up." 15)
)

Write-Page $price "Price & Calendar Drivers" @(
    (New-TextBox "30000000000000000001" 30 18 900 60 10 "Price & Calendar Drivers" "Separate demand changes caused by price, seasonality, events and SNAP timing"),
    (New-Slicer "30000000000000000002" 940 24 220 46 11 "DIM_CALENDAR" "CALENDAR_DATE" "Period"),
    (New-Slicer "30000000000000000003" 1175 24 120 46 12 "DIM_ITEM" "CAT_ID" "Category"),
    (New-Slicer "30000000000000000004" 1310 24 100 46 13 "DIM_STORE" "STATE_ID" "State"),
    (New-Card "30000000000000000005" 30 100 260 105 20 "Avg Selling Price" "Average Selling Price"),
    (New-Card "30000000000000000006" 305 100 260 105 21 "Price Change %" "Price Movement"),
    (New-Card "30000000000000000007" 580 100 260 105 22 "Holiday Revenue Share %" "Holiday Revenue Share"),
    (New-Card "30000000000000000008" 855 100 260 105 23 "SNAP Revenue Share %" "SNAP Revenue Share"),
    (New-Card "30000000000000000009" 1130 100 280 105 24 "Pricing Signal" "Pricing Signal"),
    (New-Chart "3000000000000000000a" 30 230 675 300 30 "clusteredColumnChart" "DIM_ITEM" "CAT_ID" @("Avg Selling Price", "Total Units") "Price and demand by category"),
    (New-Chart "3000000000000000000b" 735 230 675 300 31 "clusteredColumnChart" "DIM_CALENDAR" "Day Type" @("Total Revenue") "Weekday versus weekend revenue"),
    (New-Chart "3000000000000000000c" 30 560 880 190 40 "clusteredBarChart" "DIM_CALENDAR" "EVENT_TYPE_1" @("Total Revenue") "Revenue by primary event type"),
    (New-TextBox "3000000000000000000d" 940 560 470 190 41 "Decision rule" "Avoid treating correlation as elasticity. First compare price movement with category mix, event timing and store/state filters. Use targeted tests before changing broad pricing." 15)
)

Write-Page $forecast "Forecast Control Tower" @(
    (New-TextBox "40000000000000000001" 30 18 900 60 10 "Forecast Control Tower" "Future demand outlook, uncertainty bands and inventory decision triggers"),
    (New-Slicer "40000000000000000002" 940 24 220 46 11 "DIM_CALENDAR" "CALENDAR_DATE" "Period"),
    (New-Slicer "40000000000000000003" 1175 24 120 46 12 "DIM_ITEM" "CAT_ID" "Category"),
    (New-Slicer "40000000000000000004" 1310 24 100 46 13 "DIM_ITEM" "ITEM_ID" "Item"),
    (New-Card "40000000000000000005" 30 100 260 105 20 "Forecast Units" "Forecast Units"),
    (New-Card "40000000000000000006" 305 100 260 105 21 "Forecast Revenue" "Forecast Revenue"),
    (New-Card "40000000000000000007" 580 100 260 105 22 "Forecast Interval Width %" "Uncertainty Width"),
    (New-Card "40000000000000000008" 855 100 260 105 23 "Forecast Risk Status" "Risk Status"),
    (New-Card "40000000000000000009" 1130 100 280 105 24 "Recommended Action" "Action"),
    (New-Chart "4000000000000000000a" 30 230 900 300 30 "lineChart" "DIM_CALENDAR" "CALENDAR_DATE" @("Actual Units", "Forecast Units", "Forecast Upper 95", "Forecast Lower 95") "History and forecast with 95% interval"),
    (New-Chart "4000000000000000000b" 960 230 450 300 31 "clusteredBarChart" "DIM_ITEM" "CAT_ID" @("Forecast Units") "Forecast demand by category"),
    (New-Matrix "4000000000000000000c" 30 560 900 190 40 "DIM_ITEM" "ITEM_ID" @("Forecast Units", "Forecast Revenue", "Forecast Interval Width %") "Item-level forecast watchlist"),
    (New-TextBox "4000000000000000000d" 960 560 450 190 41 "Use correctly" "Future forecast rows have no observed actuals yet. The interval is a planning range, not an accuracy score. Replenish earlier and review more often when uncertainty is high." 15)
)

Write-Page $action "Action & Risk Center" @(
    (New-TextBox "50000000000000000001" 30 18 900 60 10 "Action & Risk Center" "Turn signals into explicit operating actions with clear ownership prompts"),
    (New-Slicer "50000000000000000002" 940 24 220 46 11 "DIM_CALENDAR" "CALENDAR_DATE" "Period"),
    (New-Slicer "50000000000000000003" 1175 24 120 46 12 "DIM_ITEM" "CAT_ID" "Category"),
    (New-Slicer "50000000000000000004" 1310 24 100 46 13 "DIM_STORE" "STATE_ID" "State"),
    (New-Card "50000000000000000005" 30 100 260 105 20 "Demand Signal" "Demand Signal"),
    (New-Card "50000000000000000006" 305 100 260 105 21 "Forecast Risk Status" "Forecast Risk"),
    (New-Card "50000000000000000007" 580 100 375 105 22 "Recommended Action" "Recommended Action"),
    (New-Card "50000000000000000008" 970 100 440 105 23 "Model Coverage Status" "Model Coverage"),
    (New-Chart "50000000000000000009" 30 235 670 300 30 "lineChart" "DIM_CALENDAR" "CALENDAR_DATE" @("Total Revenue", "Revenue 30D Average") "Signal validation: revenue versus baseline"),
    (New-Chart "5000000000000000000a" 730 235 680 300 31 "clusteredBarChart" "DIM_STORE" "STATE_ID" @("Total Revenue", "Total Units") "State demand exposure"),
    (New-TextBox "5000000000000000000b" 30 570 430 180 40 "1. Protect availability" "High forecast uncertainty: increase replenishment cadence, retain flexible capacity and avoid committing scarce stock to low-confidence demand." 15),
    (New-TextBox "5000000000000000000c" 490 570 430 180 41 "2. Diagnose deviation" "Below-baseline demand: inspect price movement, calendar effects and store mix. Do not use a blanket promotion before isolating the driver." 15),
    (New-TextBox "5000000000000000000d" 950 570 460 180 42 "3. Validate the outcome" "Refresh after each planned action. Track the demand signal, forecast interval and category/store exposure together to avoid solving one risk while creating another." 15)
)

Write-JsonFile (Join-Path $pagesRoot "pages.json") ([pscustomobject]@{ '$schema' = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json"; pageOrder = @($overview, $demand, $price, $forecast, $action); activePageName = $overview })

Write-JsonFile (Join-Path $ProjectRoot "retail_demand_command_center.pbip") ([pscustomobject]@{
    version = "1.0"; artifacts = @([pscustomobject]@{ report = [pscustomobject]@{ path = "retail_demand_command_center.Report" } }); settings = [pscustomobject]@{ enableAutoRecovery = $true }
})

Write-Host "Retail Demand Command Center report definition created at $ProjectRoot"
