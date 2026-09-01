#!/bin/bash
# Shared string table for hook AppleScript dialogs, in Czech and English.
# Sourced by the other hook scripts; sets L_* variables for the current
# language (from `vaire get-language`, defaulting to English to match
# AppLanguage.default in VaireKit). Case statements in the sourcing
# scripts must match against these variables, not literal strings, so
# both languages stay wired to the same logic.

vaire_lang="en"
if command -v vaire >/dev/null 2>&1; then
    detected=$(vaire get-language 2>/dev/null)
    [ "$detected" = "cs" ] && vaire_lang="cs"
fi

if [ "$vaire_lang" = "en" ]; then
    L_TITLE="Vaire"
    L_SUMMARY_TITLE="Vaire — summary"
    L_NOTE_PREFIX="Note: "
    L_TASK_RUNNING_PREFIX="A task on "
    L_TASK_RUNNING_SUFFIX=" is already running for "
    L_CONTINUE_QUESTION="Continue?"
    L_NO_NEW_TASK="No (new task)"
    L_NO_NO_LOGGING="No (don't log)"
    L_FINISH="Finish"
    L_CONTINUE="Continue"
    L_LOG_TIME_PREFIX="Log time for the session in "
    L_LOG_TIME_SUFFIX="?"
    L_NO="No"
    L_WITHOUT_NOTE="Without a note"
    L_WITH_NOTE="With a note"
    L_WHAT_WILL_YOU_DO="What will you work on?"
    L_WORKED_ON_PREFIX="Worked on "
    L_NOTE_LABEL="Note: "
    L_ESTIMATE_WITHOUT_AI="Estimate without AI: "
    L_SAVED_SUFFIX="h (saved ~"
    L_HOURS_SUFFIX="h)"
    L_DISCARD="Discard"
    L_EDIT="Edit"
    L_OK="OK"
    L_HOW_MANY_MINUTES="How many minutes, really?"
    L_NOTE_COLON="Note:"
    L_ESTIMATE_HOURS_COLON="Estimate without AI (hours):"
    L_NUMBER_ONLY_WARNING="Please enter a number only."
    L_DECIMAL_WARNING="Please enter a number (e.g. 2.5)."
else
    L_TITLE="Vaire"
    L_SUMMARY_TITLE="Vaire — shrnutí"
    L_NOTE_PREFIX="Poznámka: "
    L_TASK_RUNNING_PREFIX="Rozjetý task na "
    L_TASK_RUNNING_SUFFIX=" už běží "
    L_CONTINUE_QUESTION="Pokračovat?"
    L_NO_NEW_TASK="Ne (nový task)"
    L_NO_NO_LOGGING="Ne (bez logování)"
    L_FINISH="Dokončit"
    L_CONTINUE="Pokračovat"
    L_LOG_TIME_PREFIX="Logovat čas pro session v "
    L_LOG_TIME_SUFFIX="?"
    L_NO="Ne"
    L_WITHOUT_NOTE="Bez poznámky"
    L_WITH_NOTE="S poznámkou"
    L_WHAT_WILL_YOU_DO="Co budeš dělat?"
    L_WORKED_ON_PREFIX="Odpracováno na "
    L_NOTE_LABEL="Poznámka: "
    L_ESTIMATE_WITHOUT_AI="Odhad bez AI: "
    L_SAVED_SUFFIX="h (ušetřeno ~"
    L_HOURS_SUFFIX="h)"
    L_DISCARD="Zahodit"
    L_EDIT="Upravit"
    L_OK="OK"
    L_HOW_MANY_MINUTES="Kolik minut opravdu?"
    L_NOTE_COLON="Poznámka:"
    L_ESTIMATE_HOURS_COLON="Odhad bez AI (hodiny):"
    L_NUMBER_ONLY_WARNING="Zadej prosím jen číslo."
    L_DECIMAL_WARNING="Zadej prosím číslo (např. 2.5)."
fi
