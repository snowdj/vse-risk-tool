# Risk Tool V2

# Load all libraries and set default directories ----
source("setup.R")

# Load functions to create tables and figures
source("dynamic-table.R")
source("occupation-industry-plots.R")


# Load data for each province ----

# Ensure that identifiers have type character
data <- read_csv(file.path(OUT, "BC", "occ4_ind3.csv"),
                 col_types = cols(ind_2_digit = "c",
                                  occ_2_digit_40 = "c", 
                                  ind_3_digit = "c", 
                                  occ_4_digit = "c"))

data_agg <- read_csv(file.path(OUT, "BC", "occ2_ind2.csv"),
                     col_types = cols(ind_2_digit = "c",
                                      occ_2_digit_40 = "c"))

# Only keep occupations with enough workers
plot_data <- data_agg %>% filter(share_workers_major >= 0.01)

this <- list() # Container for this province's results --- will be replaced on demand
this$tables <- create_tables(data)
this$plots <- create_plots(plot_data) 

options(DT.options = list(
    autowidth = TRUE,
    scrollX = TRUE,
    deferRender = TRUE,
    searchHighlight = TRUE))
    
# Breaks and colors for risk column
brks <- seq(-50, 150, 1) # Leave a 50 unit buffer on each side so text is readable
clrs <- colorRampPalette(brewer.pal(9, "Reds"))(length(brks) + 1)

# Create occupation-industry scatterplots ----

ui <- fluidPage(
    title = "VSE COVID Risk/Reward Assessment Tool",
    tags$head(includeHTML(("google-analytics.html"))),
    
    h1("VSE COVID Risk/Reward Assessment Tool"),
    h2("Purpose"),
    helpText("The VSE COVID Risk/Reward Assessment Tool (VSE COVID Risk Tool, hereafter) can be used to compare some of the risks and benefits of re-opening different sectors of the economy. It features an interactive figure, where risk is represented on the vertical axis and benefit, on the horizontal axis. Each sector of the economy is listed at the right of the figure and identified by a different color. Distinct occupations within a sector are identified by bubbles, where larger bubbles represent occupations that employ a greater share of a sector’s labour force."),
    helpText("This tool also includes a table that provides more detailed information on the risk presented in the figure. First, it shows a finer breakdown of sectors and occupations. Second, in addition to the value of the risk index, it shows the value of the factors that contribute to the index, as well as other factors which may be relevant but do not enter the risk index directly. Users can navigate through the different tabs of the table to view these factors, which are broken down in three categories: risks associated with work in a particular occupation (\"Job description detail\"), importance of the sector in the BC economy (\"Economic factors detail\"), and risks associated with factors outside of the work place (\"Household detail\")."),
    helpText("Please refer to the ", tags$a(href="https://www.dropbox.com/s/5lvfyki4lfxw0ob/VSE%20Risk%20Tool%20Users%20Guide.pdf?dl=0", "User's Guide", target = "_blank"), " for a complete description of the construction of this tool and its use. The code repository for the tool is ", tags$a(href="https://github.com/pbaylis/vse-risk-tool", "here.", target = "_blank")),
    h2("Instructions"),
    helpText("1. Refer to the figure for a broad view of all sectors and occupations. You can change the variable used on the horizontal axis with the dropdown below the figure."),
    helpText("2. Click on occupations (bubbles) of interest in the figure to examine those occupations in the table below in more detail. Note that the table presents more disaggregated occupations and sectors than the figure."),
    h2("Figure: Sectors and major occupation groups"),
    plotlyOutput('scatterplot'),
    fluidRow(
        column(12,
               selectInput('xaxis', 'X axis', c("Sector employment (2019 average)", 
                                                "Sector employment loss: Feb-Mar",
                                                "Sector employment loss: Feb-Mar (bottom quartile income)",
                                                "Sector GDP share")
               )
        )
    ),
    
    hr(),
    
    h2("Table: Subsector and occupation unit groups"),
    
    tabsetPanel(
        id = 'tabset',
        tabPanel("Main", DT::dataTableOutput("table_main"),
                 hr(),
                 h3("Definitions of key main table variables"),
                 tags$ul(
                     tags$li("VSE Risk Index (Factor model): Risk index constructed using a factor model approach, includes both occupational and demographic factors."),
                     tags$li("Alt Risk Index (Simple means): Risk index constructed using signed simple means, includes both occupational and demographic factors."),
                     tags$li("Workers: Number of workers in this subsector and occupation (unit group) combination.")
                 )),
        tabPanel("Job description detail", 
                 DT::dataTableOutput("table_risk"),
                 hr(),
                 h3("Definitions of key job description variables"),
                 tags$ul(
                     tags$li("Physical proximity: Extent the job requires close physical proximity to others."),
                     tags$li("Deal with public: Importance of dealing directly with the public or performing for people."),
                     tags$li("Face to face: Frequency the job requires face-to-face discussions with others."),
                     tags$li("Assisting and caring: Importance of providing personal assistance, medical attention, emotional support, other personal care"),
                     tags$li("Exposed to weather: Frequency the job requires working outdoors, exposed to weather."),
                     tags$li("Exposed to disease: Frequency the job requires exposure to disease/infections."),
                     tags$li("Contact with others: Frequency the job requires contact with others (face-to-face, by telephone, or otherwise)."),
                     tags$li("External customers: Importance of working with external customers or the public.")
                 )),
        tabPanel("Economic factors detail", DT::dataTableOutput("table_econ")),
        tabPanel("Household detail", DT::dataTableOutput("table_household"))
    ),
)

# Define server behavior
server <- function(input, output, session) {
    
    output$scatterplot <- renderPlotly({
        # Condition which plot is displayed on the given input
        if (input$xaxis == "Sector employment (2019 average)") {
            return(this$plots$employment)
        } else if (input$xaxis == "Sector employment loss: Feb-Mar") {
            return(this$plots$fig_loss) 
        } else if (input$xaxis == "Sector employment loss: Feb-Mar (bottom quartile income)") {
            return(this$plots$fig_bottom)
        } else if (input$xaxis == "Sector GDP share") {
            return(this$plots$fig_GDP)
        }
    }
    )
    
    # Create reactive values to respond to plotly clicks
    click_ind_2_digit <- reactiveVal()
    click_ind_2_digit("")
    click_occ_2_digit <- reactiveVal()
    click_occ_2_digit("")
    
    # Also create some non-reactive values so that tables don't get reloaded
    new_ind_2_digit <- NULL
    new_occ_2_digit <- NULL
    
    # Update reactive values on ALL tables clicks in plot
    observe({
        myClicks <- event_data("plotly_click", source = "myClickSource")
        req(myClicks)
        
        click_ind_2_digit(as.character(plot_data[myClicks$customdata, "ind_2_digit"]))
        click_occ_2_digit(as.character(plot_data[myClicks$customdata, "occ_2_digit_40"]))
        
        # Update search values for tables that have been iniatialized by user (by opening the tab)
        updateSearch(proxy_main, keywords = list(global = NULL, columns = c(click_ind_2_digit(), click_occ_2_digit())))
        updateSearch(proxy_econ, keywords = list(global = NULL, columns = c(click_ind_2_digit(), click_occ_2_digit())))
        updateSearch(proxy_risk, keywords = list(global = NULL, columns = c(click_ind_2_digit(), click_occ_2_digit())))
        updateSearch(proxy_household, keywords = list(global = NULL, columns = c(click_ind_2_digit(), click_occ_2_digit())))
        
        # Tables that haven't been initialized will use these values 
        new_ind_2_digit <<- click_ind_2_digit()
        new_occ_2_digit <<- click_occ_2_digit()
    })

    # Create an options list with a default filter of 100 or greater on the number of workers
    options_list <- list(
        searchCols = list(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                          list(search = "0.001 ... Inf")))
    
    output$table_main <- DT::renderDataTable({
        round_cols_main <- this$tables$main %>% select(contains("risk index")) %>% colnames()
        
        datatable(this$tables$main, 
                  filter = list(position = "top", clear = F, plain = TRUE),
                  rownames = F,
                  options = options_list) %>% 
        formatRound(round_cols_main, 0) %>%
        formatRound("Occupation (unit group) share of sector workers", 4) %>%
        formatPercentage(grep("%", names(this$tables$main), value = T), 2) %>%
        formatStyle(
            "VSE Risk Index (Factor model)",
            backgroundColor  = styleInterval(cuts = brks, 
                                             values = clrs))
    
    })

    output$table_risk <- DT::renderDataTable({
        # Create an options list for the rest of the tables
        options_list2 <- options_list
        options_list2$searchCols[[1]] <- list(search = new_ind_2_digit)
        options_list2$searchCols[[2]] <- list(search = new_occ_2_digit)
        
        round_cols_risk <- this$tables$risk %>% select(contains("risk index"), "Physical proximity":"External customers") %>% colnames()
        
        datatable(this$tables$risk, 
                  filter = list(position = "top", clear = F, plain = TRUE),
                  rownames = F,
                  options = options_list2) %>%
            formatRound(round_cols_risk, 0) %>%
            formatRound("Occupation (unit group) share of sector workers", 4) %>%
            formatPercentage(grep("%", names(this$tables$risk), value = T), 2) %>%
            formatStyle(
                "VSE Risk Index (Factor model)",
                backgroundColor = styleInterval(cuts = brks, 
                                                 values = clrs))
        
    })

    

    
    output$table_econ <- DT::renderDataTable({
        # Create an options list for the rest of the tables
        options_list2 <- options_list
        options_list2$searchCols[[1]] <- list(search = new_ind_2_digit)
        options_list2$searchCols[[2]] <- list(search = new_occ_2_digit)
        
        round_cols_econ <- this$tables$econ %>% select(contains("risk index"), "Sector employment (average 2019)", "Sector employment change", "Sector employment change (bottom quartile)") %>% colnames()
        
        datatable(this$tables$econ, 
                  filter = list(position = "top", clear = F, plain = TRUE),
                  rownames = F,
                  options = options_list2) %>%
            formatRound(round_cols_econ, 0) %>%
            formatRound("Occupation (unit group) share of sector workers", 4) %>%
            formatPercentage(grep("%", names(this$tables$econ), value = T), 2) %>%
            formatStyle(
                "VSE Risk Index (Factor model)",
                backgroundColor  = styleInterval(cuts = brks, 
                                                 values = clrs))
    })
    
    output$table_household <- DT::renderDataTable({
        # Create an options list with the clicked filters already set, if they exist
        options_list2 <- options_list
        options_list2$searchCols[[1]] <- list(search = new_ind_2_digit)
        options_list2$searchCols[[2]] <- list(search = new_occ_2_digit)
        
        round_cols_household <- this$tables$household %>% select(contains("risk index")) %>% colnames()
        
        this$tables$household %>% 
            datatable(filter = list(position = "top", clear = F, plain = TRUE),
                      rownames = F,
                      options = options_list2) %>%
            formatPercentage(grep("%", names(this$tables$household), value = T), 2) %>%
            formatRound(round_cols_household, 0) %>%
            formatRound("Occupation (unit group) share of sector workers", 4) %>%
            formatStyle(
                "VSE Risk Index (Factor model)",
                backgroundColor  = styleInterval(cuts = brks, 
                                                 values = clrs))
    })
    

    # Set up reactive values to take in clicks from plot
    
    # Create proxy tables so that we don't have to reload the whole table
    proxy_main <- DT::dataTableProxy('table_main')
    proxy_econ <- DT::dataTableProxy('table_econ')
    proxy_risk <- DT::dataTableProxy('table_risk')
    proxy_household <- DT::dataTableProxy('table_household')
    
    
    

}

# Run the application 
shinyApp(ui = ui, server = server)
