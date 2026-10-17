@echo off
rem Back up and clear Azeroth Ledger Collection data. Close WoW first.
rem Usage: reset-collection.cmd [--dry-run] [--wow-root PATH]
python "%~dp0reset_collection.py" %*
