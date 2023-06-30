# Functions for reading and processing House and Senate Journals
# Author: Matthew Voss

library(dplyr)
library(pdftools)
library(stringr)
library(readr)



### Senate Journal
# "INTRODUCTION OF BILLS"
# "FINAL COMMITTEE REPORTS OF BILL ACTION" marks bills voted on in committee
# "CONSIDERATION OF BILL" or "CONSIDERATION OF BILLS" marks bills voted on on floor

### House Journal
# "INTRODUCTION OF BILLS"
# "COMMITTEE RECOMMENDATIONS" marks bills voted on in committee - text formatted differently than Senate
# "CONSIDERATION OF BILLS" marks bills voted on on floor - looks to be same format as Senate

# orig_text <- pdf_text("data/Journals/89th General Assembly/Senate/20220202_SJNL.pdf")
# orig_text <- pdf_text("data/Journals/89th General Assembly/Senate/20220314_SJNL.pdf")
# orig_text <- pdf_text("data/Journals/90th General Assembly/Senate/20230214_SJNL.pdf")
# orig_text <- pdf_text("data/Journals/90th General Assembly/Senate/20230307_SJNL.pdf")


# house_journal <- "data/Journals/90th General Assembly/House/20230321_HJNL.pdf"
# senate_journal <- "data/Journals/90th General Assembly/Senate/20230214_SJNL.pdf"
# 
# leg_actions = data.frame()

legislators <- read_rds("data/legislators_90th_ga.rds") |>
  mutate(
    plain_name = str_remove_all(Name, "[A-Za-z]+\\.") |> str_squish() |> str_trim(),
    last_name = word(plain_name, start = -1)
  ) |>
  group_by(Chamber, last_name) |>
  add_count(name = "last_name_count") |>
  ungroup() |>
  mutate(
    initial_last = ifelse(last_name_count > 1, yes = paste0(last_name, ", ", str_sub(Name, start = 1, end = 1), "."), no = last_name),
    initial_first = ifelse(last_name_count > 1, yes = paste0(str_sub(Name, start = 1, end = 1), ". ", last_name), no = last_name)
  ) |>
  select(-plain_name, -last_name, -last_name_count, -sponsor, -floor_manager)


create_intro_df <- function(leg_df, leg_name_var, intro_names, bill, remove_na = FALSE, chamber = c("House", "Senate")){
  return_df <- leg_df |>
    filter(Chamber %in% chamber) |>
    mutate(
      sponsored_bill = case_when(
        str_detect(intro_names, {{leg_name_var}}) ~ bill
      )
    )
  
  if(remove_na == TRUE){
    return_df <- return_df |>
      filter(!is.na(sponsored_bill))
  }
  
  return(return_df)
}

create_vote_df <- function(leg_df, leg_name_var, yea_votes, nay_votes, abs_votes = "", assume_abs = TRUE, remove_na = FALSE, chamber = c("House", "Senate")){
  return_df <- leg_df |>
    filter(Chamber %in% chamber) |>
    mutate(
      vote = case_when(
        str_detect(yea_votes, {{leg_name_var}}) ~ "Yea",
        str_detect(nay_votes, {{leg_name_var}}) ~ "Nay",
        str_detect(abs_votes, {{leg_name_var}}) ~ "Absent or Not Voting",
        TRUE ~ ifelse(assume_abs, yes = "Absent or Not Voting", no = NA_character_)
      )
    )
  
  if(remove_na == TRUE){
    return_df <- return_df |>
      filter(!is.na(vote))
  }
  
  return(return_df)
}


# journal_file <- house_journal
read_journal <- function(journal_file, legislature_df, chamber){
  
  orig_text <- pdf_text(journal_file)
  
  journal <- orig_text[-1] |>
    str_replace_all("\\\r\\\n", "~newline~") |>
    str_replace_all("\\\n", "~newline~") |>
    str_remove_all("^\\d.+Day~newline~") |>
    str_remove_all("^\\d.+\\d~newline~") |>
    # str_replace_all("(~newline~)+", "~newline~") |>
    str_trim() |>
    str_squish() |>
    str_flatten(collapse = "~newpage~")
  
  # Introduction of Bills ---------------------------------------------------
  
  # intro_start = str_locate(journal, "INTRODUCTION OF BILLS?~newline~")[[1]][2] + 1
  intro_locations <- str_locate_all(journal, "INTRODUCTION OF BILLS?~newline~")[[1]]
  
  all_intro_files <- NULL

  for(i in 1:(length(intro_locations)/2)){
    
    if(length(intro_locations) == 0){break}
    
    intro_start <- intro_locations[[i, 2]]
    process <- str_sub(journal, start = intro_start)
    
    intro <- str_sub(process, start = 1, end = str_locate(process, "[A-Z\\s]+~newline~")[1])
    
    intro_files <- str_locate_all(intro, "(Senate|House) File \\d+,")[[1]] |> as.data.frame()
    intro_files$section_end = NA_integer_
    
    for(j in 1:(nrow(intro_files))){
      end_index = ifelse(j == (nrow(intro_files)), no = intro_files$start[j+1] - 1, yes = str_length(intro))
      
      intro_files$section_end[j] = end_index
    }
    
    intro_files <- intro_files |>
      mutate(
        file_name = str_sub(intro, start = start, end = end - 1) |> str_trim(),
        file_info = str_sub(intro, start = end + 2, end = section_end) |>
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish(),
        introduced_by = str_extract(file_info, "by .*, a bill") |>
          str_remove_all("by ") |>
          str_remove_all(", a bill") |>
          str_trim() |>
          str_squish(),
        summary = str_extract(file_info, "a bill .*\\. Read") |>
          str_remove("\\. Read$") |>
          str_trim() |>
          str_squish(),
        action = str_extract(file_info, "Read .+$")
      ) |>
      rowwise() |>
      mutate(
        intro_record = list(create_intro_df(
          legislators, initial_first,
          introduced_by, file_name, chamber = chamber, remove_na = TRUE
        ))
      ) |>
      ungroup()
    
    if(is.null(all_intro_files)){
      all_intro_files <- intro_files
    } else{
      all_intro_files <- bind_rows(all_intro_files, intro_files)
    }
  }

  
  
  
  # Committee Action Reports ------------------------------------------------
  
  if(chamber == "Senate"){
    
    committee_start = str_locate_all(journal, "FINAL COMMITTEE REPORTS? OF BILL ACTION~newline~")[[1]][2] + 1
    committee_action <- str_sub(journal, start = committee_start)
    
    
    committee_files <- str_locate_all(committee_action, "[A-Z\\s:]+(~newline~)+Bill Title:")[[1]] |> as.data.frame()
    
    for(i in 1:(nrow(committee_files))){
      end_index = ifelse(i == (nrow(committee_files)), no = committee_files$start[i+1] - 1, yes = str_length(committee_action))
      
      committee_files$section_end[i] = end_index
    }
    
    committee_files <- committee_files |>
      mutate(
        info = str_sub(committee_action, start = start, end = section_end),
        committee = str_extract(info, "[A-Z:\\s]+~newline~") |> 
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish(),
        committee = ifelse(committee == "ALSO:", yes = NA, no = committee),
        file_name = str_extract(info, "Bill Title: [A-Z\\s\\*]+\\d+") |> 
          str_remove("Bill Title: ") |> 
          str_remove("\\*") |>
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish(),
        file_prev = str_extract(info, "\\([A-Z\\s0-9]+\\)") |> 
          str_remove("\\(") |> 
          str_remove("\\)") |>
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish(),
        file_info = str_extract(info, "Bill Title: .+") |> 
          str_remove("Bill Title:") |> 
          str_remove("Recommendation: .+$") |>
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish(),
        recommendation = str_extract(info, "Recommendation: .+") |>
          str_remove("Recommendation: ") |>
          str_remove("Final Vote: .+$") |>
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish(),
        vote = str_extract(info, "Final Vote: .+") |>
          str_remove("Final Vote: ") |>
          str_remove("Fiscal Note: .+$") |>
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish(),
        vote_yea = str_extract(vote, "Yeas.+") |>
          str_remove("Nays.+$"),
        vote_nay = str_extract(vote, "Nays.+") |>
          str_remove("Excused.+$"),
        vote_exc = str_extract(vote, "Excused.+$"),
        vote_yea_num = ifelse(
          str_detect(vote_yea, "none"),
          yes = 0,
          no = str_extract(vote_yea, "\\d+") |> as.numeric()
        ),
        vote_nay_num = ifelse(
          str_detect(vote_nay, "none"),
          yes = 0,
          no = str_extract(vote_nay, "\\d+") |> as.numeric()
        ),
        vote_exc_num = ifelse(
          str_detect(vote_exc, "none"),
          yes = 0,
          no = str_extract(vote_exc, "\\d+") |> as.numeric()
        ),
        vote_yea = str_remove(vote_yea, "[^:]+: "),
        vote_nay = str_remove(vote_nay, "[^:]+: "),
        vote_exc = str_remove(vote_exc, "[^:]+: "),
        vote_total = vote_yea_num + vote_nay_num,
        committee_total = vote_total + vote_exc_num,
        vote_yea_pct = (vote_yea_num / vote_total) * 100,
        vote_nay_pct = (vote_nay_num / vote_total) * 100,
        fiscal_note = str_extract(info, "Fiscal Note: .+") |>
          str_remove("Fiscal Note: ") |>
          str_remove("\\*.+$") |>
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish(),
        notes = str_extract(info, "Fiscal Note: .+") |>
          str_extract("\\*.+$") |>
          str_replace_all("~newline~", " ") |>
          str_replace_all("~newpage~", " ") |>
          str_trim() |>
          str_squish()
        
      ) |>
      tidyr::fill(
        committee, .direction = "down"
      )
    
    if(nrow(committee_files) > 0){
      committee_files <- committee_files |>
        rowwise() |>
        mutate(
          vote_record = list(create_vote_df(
            legislators, initial_first,
            vote_yea, vote_nay, abs_votes = vote_exc, assume_abs = FALSE, remove_na = TRUE, chamber = chamber
          ))
        ) |>
        ungroup()
    } 
  
  } else if(chamber == "House"){
    committee_files <- data.frame()
    # committee_start = str_locate_all(journal, "COMMITTEE RECOMMENDATIONS?~newline~")[[1]][2] + 1
    # committee_action <- str_sub(journal, start = committee_start)
    # 
    # 
    # committee_files <- str_locate_all(committee_action, "[A-Z\\s:]+(~newline~)+Bill Title:")[[1]] |> as.data.frame()
    # 
    # for(i in 1:(nrow(committee_files))){
    #   end_index = ifelse(i == (nrow(committee_files)), no = committee_files$start[i+1] - 1, yes = str_length(committee_action))
    #   
    #   committee_files$section_end[i] = end_index
    # }
    # 
    # committee_files <- committee_files |>
    #   mutate(
    #     info = str_sub(committee_action, start = start, end = section_end),
    #     committee = str_extract(info, "[A-Z:\\s]+~newline~") |> 
    #       str_replace_all("~newline~", " ") |>
    #       str_replace_all("~newpage~", " ") |>
    #       str_trim() |>
    #       str_squish(),
    #     committee = ifelse(committee == "ALSO:", yes = NA, no = committee),
    #     file_name = str_extract(info, "Bill Title: [A-Z\\s\\*]+\\d+") |> 
    #       str_remove("Bill Title: ") |> 
    #       str_remove("\\*") |>
    #       str_replace_all("~newline~", " ") |>
    #       str_replace_all("~newpage~", " ") |>
    #       str_trim() |>
    #       str_squish(),
    #     file_prev = str_extract(info, "\\([A-Z\\s0-9]+\\)") |> 
    #       str_remove("\\(") |> 
    #       str_remove("\\)") |>
    #       str_replace_all("~newline~", " ") |>
    #       str_replace_all("~newpage~", " ") |>
    #       str_trim() |>
    #       str_squish(),
    #     file_info = str_extract(info, "Bill Title: .+") |> 
    #       str_remove("Bill Title:") |> 
    #       str_remove("Recommendation: .+$") |>
    #       str_replace_all("~newline~", " ") |>
    #       str_replace_all("~newpage~", " ") |>
    #       str_trim() |>
    #       str_squish(),
    #     recommendation = str_extract(info, "Recommendation: .+") |>
    #       str_remove("Recommendation: ") |>
    #       str_remove("Final Vote: .+$") |>
    #       str_replace_all("~newline~", " ") |>
    #       str_replace_all("~newpage~", " ") |>
    #       str_trim() |>
    #       str_squish(),
    #     vote = str_extract(info, "Final Vote: .+") |>
    #       str_remove("Final Vote: ") |>
    #       str_remove("Fiscal Note: .+$") |>
    #       str_replace_all("~newline~", " ") |>
    #       str_replace_all("~newpage~", " ") |>
    #       str_trim() |>
    #       str_squish(),
    #     vote_yea = str_extract(vote, "Yeas.+") |>
    #       str_remove("Nays.+$"),
    #     vote_nay = str_extract(vote, "Nays.+") |>
    #       str_remove("Excused.+$"),
    #     vote_exc = str_extract(vote, "Excused.+$"),
    #     vote_yea_num = ifelse(
    #       str_detect(vote_yea, "none"),
    #       yes = 0,
    #       no = str_extract(vote_yea, "\\d+") |> as.numeric()
    #     ),
    #     vote_nay_num = ifelse(
    #       str_detect(vote_nay, "none"),
    #       yes = 0,
    #       no = str_extract(vote_nay, "\\d+") |> as.numeric()
    #     ),
    #     vote_exc_num = ifelse(
    #       str_detect(vote_exc, "none"),
    #       yes = 0,
    #       no = str_extract(vote_exc, "\\d+") |> as.numeric()
    #     ),
    #     vote_yea = str_remove(vote_yea, "[^:]+: "),
    #     vote_nay = str_remove(vote_nay, "[^:]+: "),
    #     vote_exc = str_remove(vote_exc, "[^:]+: "),
    #     vote_total = vote_yea_num + vote_nay_num,
    #     committee_total = vote_total + vote_exc_num,
    #     vote_yea_pct = (vote_yea_num / vote_total) * 100,
    #     vote_nay_pct = (vote_nay_num / vote_total) * 100,
    #     fiscal_note = str_extract(info, "Fiscal Note: .+") |>
    #       str_remove("Fiscal Note: ") |>
    #       str_remove("\\*.+$") |>
    #       str_replace_all("~newline~", " ") |>
    #       str_replace_all("~newpage~", " ") |>
    #       str_trim() |>
    #       str_squish(),
    #     notes = str_extract(info, "Fiscal Note: .+") |>
    #       str_extract("\\*.+$") |>
    #       str_replace_all("~newline~", " ") |>
    #       str_replace_all("~newpage~", " ") |>
    #       str_trim() |>
    #       str_squish()
    #     
    #   ) |>
    #   tidyr::fill(
    #     committee, .direction = "down"
    #   )
    # 
    # if(nrow(committee_files) > 0){
    #   committee_files <- committee_files |>
    #     rowwise() |>
    #     mutate(
    #       vote_record = list(create_vote_df(
    #         legislators, initial_first,
    #         vote_yea, vote_nay, abs_votes = vote_exc, assume_abs = FALSE, remove_na = TRUE, chamber = chamber
    #       ))
    #     ) |>
    #     ungroup()
  }
    
  
  
  # Floor Consideration -----------------------------------------------------
  
  floor_start = str_locate_all(journal, "CONSIDERATION OF [A-Z]+~newline~")[[1]][2] + 1
  
  vote_start <- ifelse(chamber == "Senate", yes = "On the question [^:]+", no = "On the question [^)]+")
  votes <- str_locate_all(journal, vote_start) |> as.data.frame()
  
  votes <- votes |>
    mutate(
      question = str_sub(journal, start = start, end = end + 1),
      vote_type = str_extract(question, "bill|resolution|amendment")
    )
  
  amendment_votes <- votes |>
    filter(vote_type == "amendment")
  
  
  bill_votes <- votes |>
    filter(vote_type != "amendment") |>
    mutate(
      bill = str_extract(question, "\\([^)]+\\)") |>
        str_sub(start = 2, end = -2) |>
        str_replace_all("~newline~", " ") |>
        str_replace_all("~newpage~", " ") |>
        str_trim() |>
        str_squish(),
      vote = str_sub(journal, end),
      vote_yea = str_sub(journal, end) |>
        str_extract("Yeas, [none0-9]+[.:][^:]+|The ayes were, [none0-9]+[.:][^:]+") |>
        str_remove_all("Nays, .*|The nays were .*") |>
        str_replace_all("~newline~", " ") |>
        str_replace_all("~newpage~", " ") |>
        str_trim() |>
        str_squish(),
      vote_nay = str_sub(journal, end) |>
        str_extract("Nays, [none0-9]+[.:][^:]+|The nays were, [none0-9]+[.:][^:]+") |>
        str_remove_all("Absent, .*|Absent or not voting, .*") |>
        str_replace_all("~newline~", " ") |>
        str_replace_all("~newpage~", " ") |>
        str_trim() |>
        str_squish(),
      vote_abs = str_sub(journal, end) |>
        str_extract("Absent, [none0-9]+[.:]|Absent or not voting, [none0-9]+[.:]"),
      vote_yea_num = ifelse(
        str_detect(vote_yea, "none"),
        yes = 0,
        no = str_extract(vote_yea, "\\d+") |> as.numeric()
      ),
      vote_nay_num = ifelse(
        str_detect(vote_nay, "none"),
        yes = 0,
        no = str_extract(vote_nay, "\\d+") |> as.numeric()
      ),
      vote_abs_num = ifelse(
        str_detect(vote_abs, "none"),
        yes = 0,
        no = str_extract(vote_abs, "\\d+") |> as.numeric()
      )
    )
  
  if(nrow(bill_votes) > 0){
    bill_votes <- bill_votes |>
      rowwise() |>
      mutate(
        vote_record = list(create_vote_df(
          legislators, initial_last,
          vote_yea, vote_nay, assume_abs = FALSE, chamber = chamber
        ))
      ) |>
      ungroup()
  }
  
  return(list(all_intro_files, committee_files, bill_votes))
}


# journal_file <- "data/Journals/90th General Assembly/Senate/20230330_SJNL.pdf"
# house_journal <- "data/Journals/90th General Assembly/House/20230503_HJNL.pdf"
# test <- read_journal(journal_file, legislators, "Senate")
# test <- read_journal(house_journal, legislators, "House")
# 
# test[[1]] |> View()
# test[[2]] |> View()
# test[[3]] |> View()
