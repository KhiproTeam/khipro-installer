#!/usr/bin/env bash

set -euo pipefail

# Khipro Unified Installer
# Installs either Khipro Dark or Khipro Classic for IBus and Fcitx5.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -is | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

sort_release_tags() {
    awk '{
        tag = $0
        version = tag
        sub(/^[^0-9]*/, "", version)
        classic_priority = (tag ~ /^clsc-v/ ? 1 : 0)
        printf "%s\t%d\t%s\n", version, classic_priority, tag
    }' | sort -s -t "$(printf '\t')" -k1,1Vr -k2,2nr | cut -f3-
}

sort_tags_by_version() {
    while IFS= read -r tag; do
        version=$(printf '%s\n' "$tag" | sed -nE 's/.*([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)(\+[0-9A-Za-z.-]+)?.*/\1/p')
        if [ -n "$version" ]; then
            printf '0\t%s\t%s\n' "$version" "$tag"
        else
            printf '1\t\t%s\n' "$tag"
        fi
    done | sort -t "$(printf '\t')" -k1,1n -k2,2Vr -k3,3 | cut -f3-
}

check_package_debian() {
    dpkg -l "$1" 2>/dev/null | grep -q '^ii'
}

check_package_fedora() {
    rpm -q "$1" >/dev/null 2>&1
}

check_package_arch() {
    pacman -Q "$1" >/dev/null 2>&1
}

prompt_variant() {
    echo "=========================================="
    echo "Choose your preferred Khipro variant:"
    echo "1. KHIPRO DARK"
    echo "  (Arguably faster on PC, and certainly faster on touchscreen."
    echo "   Juktoborno forming is manual.)"
    echo "2. KHIPRO CLASSIC"
    echo "  (Juktoborno forming is automatic.)"
    echo "=========================================="
    echo ""
    read -p "Enter choice [1/2]: " variant_choice
    variant_choice=${variant_choice:-1}

    case "$variant_choice" in
        1)
            VARIANT="dark"
            REPO_URL="https://github.com/KhiproTeam/khipro-dark-m17n.git"
            REPO_DISPLAY="Khipro Dark"
            LAYOUT_NAME="bn-khipro-dark"
            LAYOUT_FILE="$LAYOUT_NAME"
            LAYOUT_INPUT_METHOD="bn khipro-dark"
            LAYOUT_ID="khipro-dark"
            LEGACY_LAYOUT_FILES=()
            install_label="Khipro Dark"
            repo_url_for_display="https://github.com/KhiproTeam/khipro-dark-m17n"
            ;;
        2)
            VARIANT="classic"
            REPO_URL="https://github.com/rank-coder/khipro-m17n.git"
            REPO_DISPLAY="Khipro Classic"
            LAYOUT_NAME="bn-khipro-classic"
            LAYOUT_FILE="$LAYOUT_NAME"
            LAYOUT_INPUT_METHOD="bn khipro-classic"
            LAYOUT_ID="khipro-classic"
            LEGACY_LAYOUT_FILES=("bn-khipro-dark" "bn-khipro")
            install_label="Khipro Classic"
            repo_url_for_display="https://github.com/rank-coder/khipro-m17n"
            ;;
        *)
            print_error "Invalid selection. Please choose 1 or 2."
            exit 1
            ;;
    esac

    echo ""
    print_status "Selected variant: ${REPO_DISPLAY}"
    print_status "Repository: ${repo_url_for_display}"
}

prompt_branch_choice() {
    print_status "Checking available versions..."
    read -p "Install stable release from the main branch? (Y/n): " branch_choice
    branch_choice=${branch_choice:-Y}

    if [[ $branch_choice =~ ^[Nn]$ ]]; then
        print_status "Fetching available release tags..."
        if [ "$VARIANT" = "dark" ]; then
            all_tags=$(git ls-remote --tags --refs "$REPO_URL" 2>/dev/null | cut -d/ -f3 | sort_tags_by_version)
        else
            all_tags=$(git ls-remote --tags --refs "$REPO_URL" 2>/dev/null | cut -d/ -f3 | sort_release_tags)
        fi

        if [ -z "$all_tags" ]; then
            print_warning "No release tags were found."
            branch_name="main"
            return
        fi

        mapfile -t tags_array <<< "$all_tags"
        total_tags=${#tags_array[@]}
        current_page=0
        items_per_page=5

        while true; do
            start_index=$((current_page * items_per_page))
            echo ""
            print_success "Available installation options (Page $((current_page + 1))):"

            current_items=()
            for ((i=0; i<items_per_page; i++)); do
                idx=$((start_index + i))
                if [ "$idx" -lt "$total_tags" ]; then
                    tag="${tags_array[$idx]}"
                    echo " $((i+1)). $tag"
                    current_items+=("$tag")
                fi
            done

            has_next_page=false
            if [ "$((start_index + items_per_page))" -lt "$total_tags" ]; then
                has_next_page=true
                echo " 6. Show next 5 releases"
            fi

            if [ "$has_next_page" = true ]; then
                branch_option=7
            else
                branch_option=$(( ${#current_items[@]} + 1 ))
            fi
            echo " $branch_option. Install from a branch"
            echo ""
            read -p "Enter number [Default: 1]: " input_ver
            input_ver=${input_ver:-1}

            if [[ "$input_ver" =~ ^[1-5]$ ]] && [ "$input_ver" -le "${#current_items[@]}" ]; then
                branch_name="${current_items[$((input_ver - 1))]}"
                print_success "Selected release: $branch_name"
                return
            elif [ "$input_ver" = "6" ] && [ "$((start_index + items_per_page))" -lt "$total_tags" ]; then
                current_page=$((current_page + 1))
            elif [ "$input_ver" = "$branch_option" ]; then
                print_status "Fetching available branches from GitHub..."
                branches=$(git ls-remote --heads "$REPO_URL" 2>/dev/null | awk '{print $2}' | sed 's#refs/heads/##' | sort)

                if [ -z "$branches" ]; then
                    print_error "Could not fetch branch list. Please check your internet connection."
                    print_status "You can view branches at: ${repo_url_for_display}/branches"
                    exit 1
                fi

                branches_array=()
                mapfile -t branches_array <<< "$branches"
                echo ""
                print_success "Available branches:"
                for i in "${!branches_array[@]}"; do
                    echo " $((i+1)). ${branches_array[$i]}"
                done
                echo ""
                read -p "Select a branch number: " branch_choice_sel

                if [[ "$branch_choice_sel" =~ ^[0-9]+$ ]] && [ "$branch_choice_sel" -ge 1 ] && [ "$branch_choice_sel" -le "${#branches_array[@]}" ]; then
                    branch_name="${branches_array[$((branch_choice_sel - 1))]}"
                    print_success "Selected branch: $branch_name"
                    return
                fi

                print_error "Invalid branch selection."
                exit 1
            else
                print_error "Invalid selection. Please enter an available option."
            fi
        done
    else
        branch_name="main"
        print_status "Using stable release (main branch)"
    fi
}

install_variant() {
    if [ "$EUID" -eq 0 ]; then
        INSTALL_DIR="/usr/share/m17n"
        ICON_DIR="/usr/share/m17n/icons"
        PRIV_SUFFIX=""
        print_status "Running as root. Installing system-wide to $INSTALL_DIR"
    else
        INSTALL_DIR="$HOME/.m17n.d"
        ICON_DIR="$HOME/.m17n.d/icons"
        PRIV_SUFFIX="-local"
        print_status "Running as user. Installing to $INSTALL_DIR"

        if [ ! -d "$INSTALL_DIR" ]; then
            print_status "Creating directory: $INSTALL_DIR"
            mkdir -p "$INSTALL_DIR"
        fi
    fi

    print_status "Checking for Git..."
    if ! command_exists git; then
        print_error "Git is not installed but required to download ${REPO_DISPLAY}."
        distro=$(detect_distro)
        case "$distro" in
            ubuntu|debian)
                print_status "To install Git on Ubuntu/Debian:"
                echo "  sudo apt update && sudo apt install git"
                ;;
            fedora|rhel|centos)
                print_status "To install Git on Fedora/RHEL/CentOS:"
                echo "  sudo dnf install git"
                ;;
            arch|manjaro)
                print_status "To install Git on Arch/Manjaro:"
                echo "  sudo pacman -S git"
                ;;
            *)
                print_status "Please install Git using your distribution's package manager."
                ;;
        esac
        exit 1
    else
        print_success "Git is installed"
    fi

    echo ""
    echo "What would you like to do?"
    echo "1. Install ${REPO_DISPLAY} (Default)"
    echo "2. Uninstall ${REPO_DISPLAY}"
    read -p "Enter choice [1/2]: " main_choice
    main_choice=${main_choice:-1}

    if [ "$main_choice" = "2" ]; then
        print_status "Uninstallation Mode Selected"

        if [ ! -d "$INSTALL_DIR" ]; then
            print_error "Installation directory does not exist: $INSTALL_DIR"
            exit 1
        fi

        installed_files=($(find "$INSTALL_DIR" -maxdepth 1 -name "bn-khipro*.mim" | sort))

        if [ ${#installed_files[@]} -eq 0 ]; then
            print_warning "No Khipro installations found in $INSTALL_DIR"
            exit 0
        fi

        echo ""
        print_status "Found the following installations:"
        for i in "${!installed_files[@]}"; do
            filename=$(basename "${installed_files[$i]}")
            echo "$((i+1)). $filename"
        done
        echo "A. Uninstall ALL versions"
        echo ""

        print_warning "Default choice is 'None' (Cancel uninstallation)"
        read -p "Select number to uninstall (or 'A' for all): " uninstall_choice

        if [ -z "$uninstall_choice" ]; then
            print_status "Cancelled. Exiting."
            exit 0
        fi

        if [[ "$uninstall_choice" =~ ^[Aa]$ ]]; then
            read -p "Are you sure you want to uninstall ALL versions? (y/N): " confirm_all
            if [[ "$confirm_all" =~ ^[Yy]$ ]]; then
                print_status "Removing all Khipro files..."
                rm -f "$INSTALL_DIR"/bn-khipro*.mim
                rm -f "$ICON_DIR"/bn-khipro*.png
                rm -f "$INSTALL_DIR"/bn-khipro*.png 2>/dev/null || true
                print_success "All versions uninstalled successfully!"
            else
                print_status "Cancelled."
            fi
            exit 0
        elif [[ "$uninstall_choice" =~ ^[0-9]+$ ]]; then
            index=$((uninstall_choice - 1))
            if [ "$index" -ge 0 ] && [ "$index" -lt "${#installed_files[@]}" ]; then
                file_to_remove="${installed_files[$index]}"
                base_name=$(basename "$file_to_remove" .mim)

                print_status "Uninstalling $base_name..."
                rm -f "$file_to_remove"
                rm -f "$ICON_DIR/$base_name.png"
                rm -f "$INSTALL_DIR/$base_name.png" 2>/dev/null || true
                print_success "Uninstallation of $base_name complete!"
                echo ""
                print_warning "COMPUTER LOG OUT KORE LOG-IN KORUN"
            else
                print_error "Invalid selection. Exiting."
                exit 1
            fi
            exit 0
        else
            print_status "Invalid input or Cancelled. Exiting."
            exit 0
        fi
    fi

    print_status "Checking input method frameworks and m17n support..."

    ibus_installed=false
    ibus_m17n_installed=false
    fcitx_installed=false
    fcitx_m17n_installed=false

    if command_exists ibus; then
        ibus_installed=true
        if check_package_debian "ibus-m17n" 2>/dev/null || check_package_fedora "ibus-m17n" 2>/dev/null || check_package_arch "ibus-m17n" 2>/dev/null; then
            ibus_m17n_installed=true
        fi
    fi

    if command_exists fcitx5; then
        fcitx_installed=true
        if check_package_debian "fcitx5-m17n" 2>/dev/null || check_package_fedora "fcitx5-m17n" 2>/dev/null || check_package_arch "fcitx5-m17n" 2>/dev/null; then
            fcitx_m17n_installed=true
        fi
    fi

    ibus_ready=false
    if [ "$ibus_installed" = true ] && [ "$ibus_m17n_installed" = true ]; then
        ibus_ready=true
    fi

    fcitx_ready=false
    if [ "$fcitx_installed" = true ] && [ "$fcitx_m17n_installed" = true ]; then
        fcitx_ready=true
    fi

    missing_packages=()
    if [ "$ibus_ready" = true ] && [ "$fcitx_ready" = true ]; then
        print_success "Both IBus and Fcitx5 are fully installed and supported."
        print_status "Suggestion: We recommend using IBus for ${REPO_DISPLAY}."
    elif [ "$ibus_ready" = true ]; then
        print_success "IBus (with m17n support) is ready."
    elif [ "$fcitx_ready" = true ]; then
        print_success "Fcitx5 (with m17n support) is ready."
    else
        print_error "No fully compatible input method framework found!"

        if [ "$ibus_installed" = false ] && [ "$fcitx_installed" = false ]; then
            print_warning "You need to install either IBus or Fcitx5 framework."
            show_install_help=true
        else
            if [ "$ibus_installed" = true ] && [ "$ibus_m17n_installed" = false ]; then
                missing_packages+=("ibus-m17n")
            fi
            if [ "$fcitx_installed" = true ] && [ "$fcitx_m17n_installed" = false ]; then
                missing_packages+=("fcitx5-m17n")
            fi
        fi

        if [ ${#missing_packages[@]} -gt 0 ]; then
            print_warning "The following packages are missing for your installed frameworks:"
            for pkg in "${missing_packages[@]}"; do
                echo "  - $pkg"
            done
            show_install_help=true
        fi

        if [ "${show_install_help:-false}" = true ]; then
            distro=$(detect_distro)
            echo ""
            case "$distro" in
                ubuntu|debian)
                    print_status "Install commands for Ubuntu/Debian:"
                    [ "$ibus_installed" = false ] && echo "  sudo apt install ibus ibus-m17n"
                    [ "$fcitx_installed" = false ] && echo "  sudo apt install fcitx5 fcitx5-m17n"
                    if [ ${#missing_packages[@]} -gt 0 ]; then
                        echo "  sudo apt install ${missing_packages[*]}"
                    fi
                    ;;
                fedora|rhel|centos)
                    print_status "Install commands for Fedora/RHEL/CentOS:"
                    [ "$ibus_installed" = false ] && echo "  sudo dnf install ibus ibus-m17n"
                    [ "$fcitx_installed" = false ] && echo "  sudo dnf install fcitx5 fcitx5-m17n"
                    if [ ${#missing_packages[@]} -gt 0 ]; then
                        echo "  sudo dnf install ${missing_packages[*]}"
                    fi
                    ;;
                arch|manjaro)
                    print_status "Install commands for Arch/Manjaro:"
                    [ "$ibus_installed" = false ] && echo "  sudo pacman -S ibus ibus-m17n"
                    [ "$fcitx_installed" = false ] && echo "  sudo pacman -S fcitx5 fcitx5-m17n"
                    if [ ${#missing_packages[@]} -gt 0 ]; then
                        echo "  sudo pacman -S ${missing_packages[*]}"
                    fi
                    ;;
                *)
                    print_status "Please install IBus or Fcitx5 along with their m17n packages."
                    ;;
            esac
        fi

        echo ""
        read -p "Do you want to continue with installation anyway? (y/N): " continue_choice
        continue_choice=${continue_choice:-N}
        if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled. Please resolve the dependencies."
            exit 1
        fi
        print_warning "Continuing installation..."
    fi

    prompt_branch_choice

    if [ "$branch_name" = "main" ]; then
        BRANCH_SUFFIX=""
    else
        clean_branch_name=$(echo "$branch_name" | tr '.' '-')
        BRANCH_SUFFIX="-${clean_branch_name}"
    fi
    FILE_SUFFIX="${BRANCH_SUFFIX}${PRIV_SUFFIX}"

    print_status "Starting ${REPO_DISPLAY} installation..."
    print_status "Cleaning up previous installations..."
    rm -f "$INSTALL_DIR"/${LAYOUT_NAME}${FILE_SUFFIX}*.mim 2>/dev/null || true
    rm -f "$INSTALL_DIR"/${LAYOUT_NAME}${FILE_SUFFIX}*.png 2>/dev/null || true
    rm -rf "/tmp/${VARIANT}-m17n" 2>/dev/null || true

    clone_target="/tmp/${VARIANT}-m17n"
    print_status "Downloading ${REPO_DISPLAY} from GitHub..."
    if [ "$branch_name" = "main" ]; then
        git clone "$REPO_URL" "$clone_target"
    else
        git clone --branch "$branch_name" "$REPO_URL" "$clone_target"
    fi

    if [ ! -d "$clone_target" ]; then
        print_error "Failed to clone repository. Please check your internet connection and branch name."
        exit 1
    fi

    print_success "Repository cloned successfully!"

    print_status "Installing keyboard files..."
    cd "$clone_target"

    if [ "$VARIANT" = "classic" ]; then
        SOURCE_LAYOUT_FILE=""
        for candidate in "$LAYOUT_FILE" "${LEGACY_LAYOUT_FILES[@]}"; do
            if [ -f "${candidate}.mim" ]; then
                SOURCE_LAYOUT_FILE="$candidate"
                break
            fi
        done

        if [ -z "$SOURCE_LAYOUT_FILE" ]; then
            print_error "Required layout file not found. Expected ${LAYOUT_FILE}.mim or a supported legacy file (${LEGACY_LAYOUT_FILES[*]})."
            exit 1
        fi

        if ! grep -Eq '^[[:space:]]*\(input-method[[:space:]]+bn[[:space:]]+[^)]+\)' "${SOURCE_LAYOUT_FILE}.mim"; then
            print_error "No Bengali input-method declaration found in ${SOURCE_LAYOUT_FILE}.mim!"
            exit 1
        fi

        TARGET_MIM="$INSTALL_DIR/${LAYOUT_FILE}${FILE_SUFFIX}.mim"
        cp "${SOURCE_LAYOUT_FILE}.mim" "$TARGET_MIM"
        print_status "Setting input-method name for installation (Suffix: $FILE_SUFFIX)..."
        sed -i -E "s/\\(input-method[[:space:]]+bn[[:space:]]+[^)]+\\)/(input-method bn ${LAYOUT_ID}${FILE_SUFFIX})/" "$TARGET_MIM"

        if [ -f "${SOURCE_LAYOUT_FILE}.png" ]; then
            print_status "Installing icon..."
            mkdir -p "$ICON_DIR/"
            cp "${SOURCE_LAYOUT_FILE}.png" "$ICON_DIR/${LAYOUT_FILE}${FILE_SUFFIX}.png"
            print_success "Icon installed!"
        else
            print_warning "Icon file not found, skipping icon installation."
        fi
    else
        if [ ! -f "${LAYOUT_NAME}.mim" ]; then
            print_error "Required file ${LAYOUT_NAME}.mim not found in the repository!"
            exit 1
        fi

        TARGET_MIM="$INSTALL_DIR/${LAYOUT_NAME}${FILE_SUFFIX}.mim"
        cp "${LAYOUT_NAME}.mim" "$TARGET_MIM"

        if [ -n "$FILE_SUFFIX" ]; then
            print_status "Modifying internal name for installation (Suffix: $FILE_SUFFIX)..."
            sed -i "s/(input-method ${LAYOUT_INPUT_METHOD})/(input-method ${LAYOUT_INPUT_METHOD}${FILE_SUFFIX})/" "$TARGET_MIM"
        fi

        if [ -f "${LAYOUT_NAME}.png" ]; then
            print_status "Installing icon..."
            mkdir -p "$ICON_DIR/"
            cp "${LAYOUT_NAME}.png" "$ICON_DIR/${LAYOUT_NAME}${FILE_SUFFIX}.png"
            print_success "Icon installed!"
        else
            print_warning "Icon file not found, skipping icon installation."
        fi
    fi

    print_success "Keyboard files installed successfully!"
    rm -rf "$clone_target"

    echo ""
    print_success "${REPO_DISPLAY} installation completed!"
    echo ""
    print_status "Next steps:"
    echo "1. Log out and log back in to restart your input method framework"
    echo "2. Add ${REPO_DISPLAY} to your input method:"

    if [ "$ibus_installed" = true ]; then
        if [ "$VARIANT" = "dark" ]; then
            echo "   - For IBus: Open IBus Preferences → Add input method: Bengali → Khipro"
        else
            echo "   - For IBus: Open IBus Preferences → Add input method: Bengali → Khipro Classic"
        fi
    fi

    if [ "$fcitx_installed" = true ]; then
        if [ "$VARIANT" = "dark" ]; then
            echo "   - For Fcitx5: Open Fcitx5 Configuration → Add Khipro keyboard"
        else
            echo "   - For Fcitx5: Open Fcitx5 Configuration → Add Khipro Classic keyboard"
        fi
    fi

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo ""
        print_warning "REMEMBER: You need to install these packages for ${REPO_DISPLAY} to work:"
        for pkg in "${missing_packages[@]}"; do
            echo "   - $pkg"
        done
    fi

    echo ""
    print_status "If you encounter any issues, please visit:"
    echo "  Our telegram group    ::    https://t.me/KhiproChat"
    echo ""
    print_warning "COMPUTER LOG OUT KORE LOG-IN KORUN"
}

prompt_variant
install_variant

