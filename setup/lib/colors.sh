#!/usr/bin/env bash
# =============================================================================
# Colors and Formatting Library
# =============================================================================
# This library provides consistent color codes and formatting functions
# for terminal output across all infrastructure scripts.
#
# Usage:
#   source "$(dirname "$0")/setup/lib/colors.sh"
#   echo -e "${GREEN}Success!${NC}"
#   success "Operation completed"
#   error "Something went wrong"
# =============================================================================

# -----------------------------------------------------------------------------
# Color Codes
# -----------------------------------------------------------------------------
# ANSI color codes for terminal output

# Regular colors
export BLACK='\033[0;30m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'

# Bold colors
export BOLD_BLACK='\033[1;30m'
export BOLD_RED='\033[1;31m'
export BOLD_GREEN='\033[1;32m'
export BOLD_YELLOW='\033[1;33m'
export BOLD_BLUE='\033[1;34m'
export BOLD_PURPLE='\033[1;35m'
export BOLD_CYAN='\033[1;36m'
export BOLD_WHITE='\033[1;37m'

# Background colors
export BG_BLACK='\033[40m'
export BG_RED='\033[41m'
export BG_GREEN='\033[42m'
export BG_YELLOW='\033[43m'
export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'
export BG_CYAN='\033[46m'
export BG_WHITE='\033[47m'

# Special formatting
export BOLD='\033[1m'
export DIM='\033[2m'
export UNDERLINE='\033[4m'
export BLINK='\033[5m'
export REVERSE='\033[7m'
export HIDDEN='\033[8m'

# Reset
export NC='\033[0m'  # No Color / Reset

# -----------------------------------------------------------------------------
# Status Icons
# -----------------------------------------------------------------------------
export ICON_SUCCESS="✓"
export ICON_ERROR="✗"
export ICON_WARNING="⚠"
export ICON_INFO="ℹ"
export ICON_QUESTION="?"
export ICON_ARROW="→"
export ICON_BULLET="•"

# -----------------------------------------------------------------------------
# Output Functions
# -----------------------------------------------------------------------------

# Success message (green with checkmark)
success() {
    echo -e "${GREEN}${ICON_SUCCESS}${NC} $*"
}

# Error message (red with X)
error() {
    echo -e "${RED}${ICON_ERROR}${NC} $*" >&2
}

# Warning message (yellow with warning icon)
warning() {
    echo -e "${YELLOW}${ICON_WARNING}${NC} $*"
}

# Info message (blue with info icon)
info() {
    echo -e "${BLUE}${ICON_INFO}${NC} $*"
}

# Question/prompt message (cyan with question mark)
question() {
    echo -e "${CYAN}${ICON_QUESTION}${NC} $*"
}

# Step message (bold with arrow)
step() {
    echo -e "${BOLD}${ICON_ARROW}${NC} $*"
}

# Bullet point message
bullet() {
    echo -e "  ${ICON_BULLET} $*"
}

# Header message (bold and underlined)
header() {
    echo -e "\n${BOLD}${UNDERLINE}$*${NC}\n"
}

# Subheader message (bold)
subheader() {
    echo -e "\n${BOLD}$*${NC}"
}

# Section separator
separator() {
    local char="${1:--}"
    local length="${2:-60}"
    printf "${DIM}%${length}s${NC}\n" | tr ' ' "$char"
}

# Box message (for important notices)
box() {
    local message="$*"
    local length=${#message}
    local border_length=$((length + 4))

    echo -e "${BOLD}"
    printf "┌%${border_length}s┐\n" | tr ' ' '─'
    echo "│  ${message}  │"
    printf "└%${border_length}s┘\n" | tr ' ' '─'
    echo -e "${NC}"
}

# -----------------------------------------------------------------------------
# Progress Indicators
# -----------------------------------------------------------------------------

# Spinner for long-running operations
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'

    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-50}

    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%%" "$percentage"

    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# Input Functions
# -----------------------------------------------------------------------------

# Prompt for yes/no confirmation
confirm() {
    local message="$1"
    local default="${2:-n}"  # Default to 'n' if not specified

    local prompt
    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    while true; do
        question "$message $prompt"
        read -r response

        # Use default if no response
        if [ -z "$response" ]; then
            response="$default"
        fi

        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) warning "Please answer yes or no.";;
        esac
    done
}

# Prompt for input with validation
prompt() {
    local message="$1"
    local var_name="$2"
    local default="${3:-}"

    while true; do
        if [ -n "$default" ]; then
            question "$message [$default]"
        else
            question "$message"
        fi

        read -r response

        # Use default if no response
        if [ -z "$response" ] && [ -n "$default" ]; then
            response="$default"
        fi

        # Validate response
        if [ -n "$response" ]; then
            eval "$var_name='$response'"
            return 0
        else
            warning "Input cannot be empty."
        fi
    done
}

# Prompt for password (hidden input)
prompt_password() {
    local message="$1"
    local var_name="$2"

    question "$message"
    read -s -r password
    echo ""  # New line after hidden input

    if [ -z "$password" ]; then
        warning "Password cannot be empty."
        return 1
    fi

    eval "$var_name='$password'"
    return 0
}

# -----------------------------------------------------------------------------
# Status Functions
# -----------------------------------------------------------------------------

# Show loading message
loading() {
    echo -ne "${BLUE}${ICON_ARROW}${NC} $* ... "
}

# Show done message (after loading)
done_msg() {
    echo -e "${GREEN}done${NC}"
}

# Show failed message (after loading)
failed_msg() {
    echo -e "${RED}failed${NC}"
}

# Show skipped message (after loading)
skipped_msg() {
    echo -e "${YELLOW}skipped${NC}"
}

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------

# Log message with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[${timestamp}] [${level}] ${message}"
}

# Log levels
log_debug() {
    log "DEBUG" "$*"
}

log_info() {
    log "INFO" "$*"
}

log_warning() {
    log "WARNING" "$*"
}

log_error() {
    log "ERROR" "$*"
}

# -----------------------------------------------------------------------------
# Formatting Functions
# -----------------------------------------------------------------------------

# Print text in color
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Print bold text
print_bold() {
    echo -e "${BOLD}$*${NC}"
}

# Print dimmed text
print_dim() {
    echo -e "${DIM}$*${NC}"
}

# Print underlined text
print_underline() {
    echo -e "${UNDERLINE}$*${NC}"
}

# -----------------------------------------------------------------------------
# Table Functions
# -----------------------------------------------------------------------------

# Print table header
table_header() {
    local -a headers=("$@")
    local header_str=""

    for header in "${headers[@]}"; do
        header_str+="$(printf "%-20s" "$header")"
    done

    echo -e "${BOLD}${header_str}${NC}"
    echo -e "${DIM}$(printf '%.0s-' {1..80})${NC}"
}

# Print table row
table_row() {
    local -a cols=("$@")
    local row_str=""

    for col in "${cols[@]}"; do
        row_str+="$(printf "%-20s" "$col")"
    done

    echo "$row_str"
}

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

# Check if terminal supports colors
supports_color() {
    if [ -t 1 ]; then
        local ncolors=$(tput colors 2>/dev/null || echo 0)
        if [ "$ncolors" -ge 8 ]; then
            return 0
        fi
    fi
    return 1
}

# Disable colors if terminal doesn't support them
disable_colors_if_unsupported() {
    if ! supports_color; then
        # Disable all color codes
        BLACK=''
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        PURPLE=''
        CYAN=''
        WHITE=''
        BOLD_BLACK=''
        BOLD_RED=''
        BOLD_GREEN=''
        BOLD_YELLOW=''
        BOLD_BLUE=''
        BOLD_PURPLE=''
        BOLD_CYAN=''
        BOLD_WHITE=''
        BG_BLACK=''
        BG_RED=''
        BG_GREEN=''
        BG_YELLOW=''
        BG_BLUE=''
        BG_PURPLE=''
        BG_CYAN=''
        BG_WHITE=''
        BOLD=''
        DIM=''
        UNDERLINE=''
        BLINK=''
        REVERSE=''
        HIDDEN=''
        NC=''

        # Update exports
        export BLACK RED GREEN YELLOW BLUE PURPLE CYAN WHITE
        export BOLD_BLACK BOLD_RED BOLD_GREEN BOLD_YELLOW BOLD_BLUE BOLD_PURPLE BOLD_CYAN BOLD_WHITE
        export BG_BLACK BG_RED BG_GREEN BG_YELLOW BG_BLUE BG_PURPLE BG_CYAN BG_WHITE
        export BOLD DIM UNDERLINE BLINK REVERSE HIDDEN NC
    fi
}

# Auto-detect and disable colors if needed
disable_colors_if_unsupported

# -----------------------------------------------------------------------------
# Export Functions
# -----------------------------------------------------------------------------
export -f success error warning info question step bullet
export -f header subheader separator box
export -f spinner progress_bar
export -f confirm prompt prompt_password
export -f loading done_msg failed_msg skipped_msg
export -f log log_debug log_info log_warning log_error
export -f print_color print_bold print_dim print_underline
export -f table_header table_row
export -f supports_color disable_colors_if_unsupported
