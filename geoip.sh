#!/usr/bin/env bash
# ============================================================
#  GeoIP Firewall Installer — AMS SOFT
#  Versão: 1.0.0
#  Autor: Adriano Medina (www.amssoft.com.br)
#  Descrição: Instalador automatizado de bloqueio GeoIP
#             baseado em geoip-shell + wrapper geoip-fw
# ============================================================

set -euo pipefail

# ─── Cores ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Caminhos ─────────────────────────────────────────────
CONF_DIR="/etc/geoip-firewall"
CONF_FILE="$CONF_DIR/config.conf"
WHITELIST_FILE="$CONF_DIR/whitelist.conf"
DOMAINS_FILE="$CONF_DIR/domains.conf"
CIDR_SOURCES_FILE="$CONF_DIR/cidr-sources.conf"
WRAPPER_BIN="/usr/local/bin/geoip-fw"
LOG_FILE="/var/log/geoip-firewall.log"
GEOIP_SHELL_DIR="/opt/geoip-shell"

# ─── Presets de continentes/regiões ───────────────────────
declare -A PRESETS
PRESETS[brazil_only]="BR"
PRESETS[south_america]="BR AR UY PY BO PE CL CO VE EC GY SR GF FK"
PRESETS[mercosul]="BR AR UY PY"
PRESETS[latin_america]="BR AR UY PY BO PE CL CO VE EC MX GT BZ HN SV NI CR PA CU DO HT JM TT BB"
PRESETS[brazil_portugal]="BR PT"
PRESETS[europe]="AL AD AT BE BA BG HR CY CZ DK EE FI FR DE GR HU IS IE IT LV LI LT LU MT ME NL MK NO PL PT RO RS SK SI ES SE CH GB"
PRESETS[north_america]="US CA MX"
PRESETS[portuguese_world]="BR PT AO MZ CV ST GW TL MO"

# Países fora das Américas com alto risco de bots e sem relação comercial com a AMS SOFT.
# Uso: geoip-fw add-continent amssoft_blacklist (no modo blacklist)
PRESETS[amssoft_blacklist]="CN RU IN VN ID BD PK EG NG TR IQ IR AF MM KH LA NP LK TH PH MY TW HK KZ UZ SA AE KW QA BH OM JO LB SY YE SD LY DZ TN MA KE GH SN ET TZ UG ZA MG JP KR"

# ═══════════════════════════════════════════════════════════
# FUNÇÕES UTILITÁRIAS
# ═══════════════════════════════════════════════════════════

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null || true
}

info()    { echo -e "${GREEN}✔${NC} $*"; log "INFO: $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; log "WARN: $*"; }
error()   { echo -e "${RED}✖${NC} $*"; log "ERROR: $*"; }
step()    { echo -e "\n${CYAN}${BOLD}► $*${NC}"; log "STEP: $*"; }
header()  { echo -e "\n${BLUE}${BOLD}$*${NC}"; }
ask()     { echo -e "${YELLOW}?${NC}  $*"; }

die() {
    error "$*"
    echo -e "\n${RED}Instalação abortada.${NC}"
    exit 1
}

# ─── Nomes dos países (ISO 3166-1 alpha-2 → pt-BR) ─────────
declare -A COUNTRY_NAMES=(
    [AD]="Andorra" [AE]="Emirados Árabes" [AF]="Afeganistão" [AG]="Antígua e Barbuda"
    [AL]="Albânia" [AM]="Armênia" [AO]="Angola" [AR]="Argentina" [AT]="Áustria"
    [AU]="Austrália" [AZ]="Azerbaijão" [BA]="Bósnia e Herzegovina" [BB]="Barbados"
    [BD]="Bangladesh" [BE]="Bélgica" [BF]="Burkina Faso" [BG]="Bulgária" [BH]="Bahrein"
    [BI]="Burundi" [BJ]="Benin" [BN]="Brunei" [BO]="Bolívia" [BR]="Brasil"
    [BS]="Bahamas" [BT]="Butão" [BW]="Botsuana" [BY]="Bielorrússia" [BZ]="Belize"
    [CA]="Canadá" [CD]="Congo (RDC)" [CF]="Rep. Centro-Africana" [CG]="Congo"
    [CH]="Suíça" [CI]="Costa do Marfim" [CL]="Chile" [CM]="Camarões" [CN]="China"
    [CO]="Colômbia" [CR]="Costa Rica" [CU]="Cuba" [CV]="Cabo Verde" [CY]="Chipre"
    [CZ]="Tchéquia" [DE]="Alemanha" [DJ]="Djibuti" [DK]="Dinamarca" [DM]="Dominica"
    [DO]="Rep. Dominicana" [DZ]="Argélia" [EC]="Equador" [EE]="Estônia" [EG]="Egito"
    [ER]="Eritreia" [ES]="Espanha" [ET]="Etiópia" [FI]="Finlândia" [FJ]="Fiji"
    [FM]="Micronésia" [FR]="França" [GA]="Gabão" [GB]="Reino Unido" [GD]="Granada"
    [GE]="Geórgia" [GF]="Guiana Francesa" [GH]="Gana" [GM]="Gâmbia" [GN]="Guiné"
    [GQ]="Guiné Equatorial" [GR]="Grécia" [GT]="Guatemala" [GW]="Guiné-Bissau"
    [GY]="Guiana" [HN]="Honduras" [HR]="Croácia" [HT]="Haiti" [HU]="Hungria"
    [ID]="Indonésia" [IE]="Irlanda" [IL]="Israel" [IN]="Índia" [IQ]="Iraque"
    [IR]="Irã" [IS]="Islândia" [IT]="Itália" [JM]="Jamaica" [JO]="Jordânia"
    [JP]="Japão" [KE]="Quênia" [KG]="Quirguistão" [KH]="Camboja" [KI]="Kiribati"
    [KM]="Comores" [KN]="São Cristóvão e Nevis" [KP]="Coreia do Norte"
    [KR]="Coreia do Sul" [KW]="Kuwait" [KZ]="Cazaquistão" [LA]="Laos" [LB]="Líbano"
    [LC]="Santa Lúcia" [LI]="Liechtenstein" [LK]="Sri Lanka" [LR]="Libéria"
    [LS]="Lesoto" [LT]="Lituânia" [LU]="Luxemburgo" [LV]="Letônia" [LY]="Líbia"
    [MA]="Marrocos" [MC]="Mônaco" [MD]="Moldávia" [ME]="Montenegro" [MG]="Madagascar"
    [MK]="Macedônia do Norte" [ML]="Mali" [MM]="Mianmar" [MN]="Mongólia"
    [MR]="Mauritânia" [MT]="Malta" [MU]="Maurício" [MV]="Maldivas" [MW]="Malawi"
    [MX]="México" [MY]="Malásia" [MZ]="Moçambique" [NA]="Namíbia" [NE]="Níger"
    [NG]="Nigéria" [NI]="Nicarágua" [NL]="Holanda" [NO]="Noruega" [NP]="Nepal"
    [NR]="Nauru" [NZ]="Nova Zelândia" [OM]="Omã" [PA]="Panamá" [PE]="Peru"
    [PG]="Papua-Nova Guiné" [PH]="Filipinas" [PK]="Paquistão" [PL]="Polônia"
    [PT]="Portugal" [PW]="Palau" [PY]="Paraguai" [QA]="Catar" [RO]="Romênia"
    [RS]="Sérvia" [RU]="Rússia" [RW]="Ruanda" [SA]="Arábia Saudita"
    [SB]="Ilhas Salomão" [SC]="Seicheles" [SD]="Sudão" [SE]="Suécia"
    [SG]="Singapura" [SI]="Eslovênia" [SK]="Eslováquia" [SL]="Serra Leoa"
    [SM]="San Marino" [SN]="Senegal" [SO]="Somália" [SR]="Suriname"
    [SS]="Sudão do Sul" [ST]="São Tomé e Príncipe" [SV]="El Salvador"
    [SY]="Síria" [SZ]="Essuatini" [TD]="Chade" [TG]="Togo" [TH]="Tailândia"
    [TJ]="Tajiquistão" [TL]="Timor-Leste" [TM]="Turcomenistão" [TN]="Tunísia"
    [TO]="Tonga" [TR]="Turquia" [TT]="Trinidad e Tobago" [TV]="Tuvalu"
    [TW]="Taiwan" [TZ]="Tanzânia" [UA]="Ucrânia" [UG]="Uganda" [US]="Estados Unidos"
    [UY]="Uruguai" [UZ]="Uzbequistão" [VA]="Vaticano" [VC]="São Vicente e Granadinas"
    [VE]="Venezuela" [VN]="Vietnã" [VU]="Vanuatu" [WS]="Samoa" [FK]="Ilhas Malvinas"
    [YE]="Iêmen" [ZA]="África do Sul" [ZM]="Zâmbia" [ZW]="Zimbábue" [MO]="Macau"
)

# Retorna o nome do país em pt-BR a partir do código ISO. Se não encontrar, retorna o próprio código.
country_name() {
    local cc="${1^^}"
    echo "${COUNTRY_NAMES[$cc]:-$cc}"
}

# Formata lista de códigos de país: "BR AR" → "BR (Brasil) AR (Argentina)"
format_countries() {
    local out="" cc
    for cc in $1; do
        out+="$cc ($(country_name "$cc")) "
    done
    echo "${out% }"
}

# ─── Carregar configuração ─────────────────────────────────
load_config() {
    [[ -f "$CONF_FILE" ]] || return 1
    # shellcheck source=/dev/null
    source "$CONF_FILE"
}

# ─── Verificar root ────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Este script precisa ser executado como root.\nUse: sudo $0"
    fi
}

# ─── Detectar OS ──────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_VERSION="${VERSION_ID:-0}"
        OS_LIKE="${ID_LIKE:-}"
    else
        die "Não foi possível detectar o sistema operacional."
    fi

    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop)
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update -qq"
            PKG_INSTALL="apt-get install -y -qq"
            ;;
        centos|rhel|almalinux|rocky|fedora)
            PKG_MANAGER="yum"
            PKG_UPDATE="yum makecache -q"
            PKG_INSTALL="yum install -y -q"
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf makecache -q"
                PKG_INSTALL="dnf install -y -q"
            fi
            ;;
        *)
            if echo "$OS_LIKE" | grep -qiE "debian|ubuntu"; then
                PKG_MANAGER="apt-get"
                PKG_UPDATE="apt-get update -qq"
                PKG_INSTALL="apt-get install -y -qq"
            elif echo "$OS_LIKE" | grep -qiE "rhel|fedora|centos"; then
                PKG_MANAGER="yum"
                PKG_UPDATE="yum makecache -q"
                PKG_INSTALL="yum install -y -q"
            else
                die "OS não suportado: $OS_ID. Suportados: Ubuntu, Debian, CentOS, RHEL, AlmaLinux, Rocky, Fedora."
            fi
            ;;
    esac

    info "OS detectado: ${BOLD}$PRETTY_NAME${NC}"
}

# ─── Detectar stack completo de firewall ─────────────────
detect_firewall() {
    FW_BACKEND=""
    FW_NEEDS_INSTALL=""
    FW_FAIL2BAN_BACKEND=""
    FW_CONFLICT_FIXED=""

    step "Analisando stack de firewall"

    local has_nftables=0 has_iptables=0 has_ufw=0 has_firewalld=0 has_fail2ban=0
    local active_nftables=0 active_iptables=0 active_ufw=0 active_firewalld=0

    command -v nft          &>/dev/null && has_nftables=1
    command -v iptables     &>/dev/null && has_iptables=1
    command -v ufw          &>/dev/null && has_ufw=1
    command -v firewall-cmd &>/dev/null && has_firewalld=1
    command -v fail2ban-client &>/dev/null && has_fail2ban=1

    # nftables: tem regras carregadas?
    if [[ $has_nftables -eq 1 ]]; then
        local nft_rules
        nft_rules=$(nft list ruleset 2>/dev/null | wc -l) || nft_rules=0
        [[ $nft_rules -gt 2 ]] && active_nftables=1
    fi

    # iptables: tem regras além do padrão?
    if [[ $has_iptables -eq 1 ]]; then
        local ipt_rules
        ipt_rules=$(iptables -L 2>/dev/null | grep -cv "^Chain\|^target\|^$" 2>/dev/null) || ipt_rules=0
        [[ $ipt_rules -gt 0 ]] && active_iptables=1
    fi

    # ufw: status
    if [[ $has_ufw -eq 1 ]]; then
        ufw status 2>/dev/null | grep -q "Status: active" && active_ufw=1
    fi

    # firewalld: rodando?
    if [[ $has_firewalld -eq 1 ]]; then
        systemctl is-active firewalld &>/dev/null && active_firewalld=1
    fi

    # Exibir o que foi encontrado
    echo ""
    if [[ $has_nftables -eq 1 ]]; then
        [[ $active_nftables -eq 1 ]] \
            && echo -e "   ${GREEN}✔${NC} nftables:   instalado (ativo com regras)" \
            || echo -e "   ${YELLOW}–${NC} nftables:   instalado (sem regras)"
    else
        echo -e "   ${RED}✖${NC} nftables:   não encontrado"
    fi

    if [[ $has_iptables -eq 1 ]]; then
        [[ $active_iptables -eq 1 ]] \
            && echo -e "   ${GREEN}✔${NC} iptables:   instalado (ativo com regras)" \
            || echo -e "   ${YELLOW}–${NC} iptables:   instalado (sem regras)"
    else
        echo -e "   ${RED}✖${NC} iptables:   não encontrado"
    fi

    if [[ $has_ufw -eq 1 ]]; then
        [[ $active_ufw -eq 1 ]] \
            && echo -e "   ${GREEN}✔${NC} ufw:        instalado (ativo)" \
            || echo -e "   ${YELLOW}–${NC} ufw:        instalado (inativo)"
    else
        echo -e "   ${YELLOW}–${NC} ufw:        não encontrado"
    fi

    if [[ $has_firewalld -eq 1 ]]; then
        [[ $active_firewalld -eq 1 ]] \
            && echo -e "   ${GREEN}✔${NC} firewalld:  instalado (ativo)" \
            || echo -e "   ${YELLOW}–${NC} firewalld:  instalado (inativo)"
    else
        echo -e "   ${YELLOW}–${NC} firewalld:  não encontrado"
    fi

    # Detectar backend do fail2ban
    if [[ $has_fail2ban -eq 1 ]]; then
        local fb_action
        fb_action=$(grep -rh "^banaction\s*=" /etc/fail2ban/jail.local /etc/fail2ban/jail.conf 2>/dev/null \
                    | head -1 | awk -F= '{print $2}' | xargs)

        if echo "$fb_action" | grep -qi "nftables"; then
            FW_FAIL2BAN_BACKEND="nftables"
        else
            FW_FAIL2BAN_BACKEND="iptables"
        fi

        echo -e "   ${GREEN}✔${NC} fail2ban:   rodando (banaction: ${fb_action:-iptables-multiport})"

        # Checar se iptables está no PATH do fail2ban-server
        if [[ "$FW_FAIL2BAN_BACKEND" == "iptables" && $has_iptables -eq 1 ]]; then
            local fb_pid fb_path
            fb_pid=$(pidof fail2ban-server 2>/dev/null || echo "")
            if [[ -n "$fb_pid" ]]; then
                fb_path=$(grep -az "PATH=" /proc/$fb_pid/environ 2>/dev/null | tr '\0' '\n' | grep "^PATH=" | head -1 || echo "")
                if [[ -n "$fb_path" ]] && ! echo "$fb_path" | grep -q "/usr/sbin"; then
                    warn "iptables não está no PATH do fail2ban-server — corrigindo..."
                    ln -sf /usr/sbin/iptables  /usr/bin/iptables  2>/dev/null || true
                    ln -sf /usr/sbin/ip6tables /usr/bin/ip6tables 2>/dev/null || true
                    FW_CONFLICT_FIXED="iptables_path"
                    info "Symlinks criados: /usr/bin/iptables → /usr/sbin/iptables"
                fi
            fi
        fi
    else
        echo -e "   ${YELLOW}–${NC} fail2ban:   não encontrado"
    fi

    echo ""

    # Decisão de backend — sem conflito, respeitando o que já existe
    if [[ $has_fail2ban -eq 1 && -n "$FW_FAIL2BAN_BACKEND" ]]; then
        FW_BACKEND="$FW_FAIL2BAN_BACKEND"
        echo -e "   ${CYAN}Decisão:${NC} usando ${BOLD}$FW_BACKEND${NC} (compatível com fail2ban em execução)"

    elif [[ $active_firewalld -eq 1 ]]; then
        FW_BACKEND="nftables"
        firewall-cmd --version 2>/dev/null | grep -q "nftables" || FW_BACKEND="iptables"
        echo -e "   ${CYAN}Decisão:${NC} usando ${BOLD}firewalld${NC} (backend: $FW_BACKEND)"

    elif [[ $active_ufw -eq 1 ]]; then
        FW_BACKEND="iptables"
        echo -e "   ${CYAN}Decisão:${NC} usando ${BOLD}iptables${NC} (ufw ativo)"

    elif [[ $active_nftables -eq 1 ]]; then
        FW_BACKEND="nftables"
        echo -e "   ${CYAN}Decisão:${NC} usando ${BOLD}nftables${NC} (ativo com regras existentes)"

    elif [[ $active_iptables -eq 1 ]]; then
        FW_BACKEND="iptables"
        echo -e "   ${CYAN}Decisão:${NC} usando ${BOLD}iptables${NC} (ativo com regras existentes)"

    elif [[ $has_nftables -eq 1 ]]; then
        FW_BACKEND="nftables"
        echo -e "   ${CYAN}Decisão:${NC} usando ${BOLD}nftables${NC} (instalado, sem regras ativas)"

    elif [[ $has_iptables -eq 1 ]]; then
        FW_BACKEND="iptables"
        echo -e "   ${CYAN}Decisão:${NC} usando ${BOLD}iptables${NC} (instalado)"

    else
        FW_BACKEND="nftables"
        FW_NEEDS_INSTALL="nftables"
        echo -e "   ${CYAN}Decisão:${NC} nenhum firewall encontrado — ${BOLD}nftables será instalado${NC}"
    fi

    if [[ -n "$FW_CONFLICT_FIXED" ]]; then
        warn "Recomendado reiniciar fail2ban após instalação: systemctl restart fail2ban"
    fi

    echo ""
    info "Firewall backend selecionado: ${BOLD}$FW_BACKEND${NC}"
}

# ─── Detectar interface de rede ───────────────────────────
detect_interface() {
    DETECTED_IF=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
    if [[ -z "$DETECTED_IF" ]]; then
        DETECTED_IF=$(ip link show | awk -F: '$0 !~/^[0-9]*: lo|link\//{gsub(/ /,"",$2); print $2}' | head -1)
    fi
    DETECTED_IF="${DETECTED_IF:-eth0}"
}

# ─── Detectar IP da sessão SSH ────────────────────────────
detect_ssh_ip() {
    SSH_CLIENT_IP=""
    if [[ -n "${SSH_CLIENT:-}" ]]; then
        SSH_CLIENT_IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
    elif [[ -n "${SSH_CONNECTION:-}" ]]; then
        SSH_CLIENT_IP=$(echo "$SSH_CONNECTION" | awk '{print $1}')
    fi
}

# ─── Verificar conectividade ──────────────────────────────
check_connectivity() {
    local ok=0

    # Teste 1: HTTPS para ipdeny.com
    if curl -s --connect-timeout 5 https://ipdeny.com > /dev/null 2>&1; then
        ok=1
    # Teste 2: HTTPS para github.com
    elif curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
        ok=1
    # Teste 3: ping para 1.1.1.1
    elif ping -c 1 -W 3 1.1.1.1 > /dev/null 2>&1; then
        ok=1
    # Teste 4: ping para 8.8.8.8
    elif ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1; then
        ok=1
    fi

    if [[ $ok -eq 1 ]]; then
        info "Conectividade com internet confirmada."
        return 0
    fi

    # Sem conectividade — perguntar se quer continuar mesmo assim
    warn "Não foi possível confirmar conectividade com a internet."
    warn "O download das listas GeoIP pode falhar mais adiante."
    echo ""
    ask "Deseja continuar mesmo assim? [s/N]: "
    read -r FORCE_CONTINUE
    if [[ "${FORCE_CONTINUE,,}" == "s" ]]; then
        warn "Continuando sem confirmação de conectividade..."
        return 0
    fi

    die "Instalação abortada. Verifique a conexão e tente novamente."
}

# ═══════════════════════════════════════════════════════════
# INSTALAÇÃO DE DEPENDÊNCIAS
# ═══════════════════════════════════════════════════════════

install_dependencies() {
    step "Instalando dependências"

    echo -e "   Atualizando repositórios..."
    $PKG_UPDATE > /dev/null 2>&1 || warn "Falha ao atualizar repositórios, continuando..."

    # Dependências base — sempre necessárias
    local PKGS="curl wget git dnsutils jq"

    # ipset só é necessário se o backend for iptables
    if [[ "$FW_BACKEND" == "iptables" ]]; then
        PKGS="$PKGS ipset"
    fi

    # Instalar firewall APENAS se nenhum foi detectado
    if [[ -n "${FW_NEEDS_INSTALL:-}" ]]; then
        warn "Nenhum firewall detectado — instalando $FW_NEEDS_INSTALL..."
        case "$FW_NEEDS_INSTALL" in
            nftables)
                PKGS="$PKGS nftables"
                ;;
            iptables)
                case "$PKG_MANAGER" in
                    apt-get) PKGS="$PKGS iptables iptables-persistent netfilter-persistent" ;;
                    yum|dnf) PKGS="$PKGS iptables iptables-services" ;;
                esac
                ;;
        esac
    else
        info "Firewall já instalado — nenhum pacote de firewall adicional necessário."
    fi

    # Instalar apenas o que está faltando
    for pkg in $PKGS; do
        local already_installed=0
        command -v "$pkg" &>/dev/null && already_installed=1
        dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && already_installed=1
        rpm -q "$pkg" &>/dev/null && already_installed=1

        if [[ $already_installed -eq 0 ]]; then
            echo -e "   Instalando ${pkg}..."
            $PKG_INSTALL "$pkg" > /dev/null 2>&1                 && info "$pkg instalado."                 || warn "Não foi possível instalar $pkg"
        else
            echo -e "   ${YELLOW}–${NC} $pkg já está instalado."
        fi
    done

    info "Dependências verificadas."
}

# ═══════════════════════════════════════════════════════════
# INSTALAR GEOIP-SHELL
# ═══════════════════════════════════════════════════════════

install_geoip_shell() {
    step "Instalando geoip-shell"

    if command -v geoip-shell &>/dev/null; then
        info "geoip-shell já está instalado."
        return 0
    fi

    if [[ -f "$GEOIP_SHELL_DIR/geoip-shell-install.sh" ]] && command -v geoip-shell &>/dev/null; then
        info "geoip-shell já instalado e clonado em $GEOIP_SHELL_DIR."
        return 0
    fi

    echo -e "   Clonando repositório geoip-shell..."
    if [[ -d "$GEOIP_SHELL_DIR" ]]; then
        rm -rf "$GEOIP_SHELL_DIR"
    fi

    git clone -q https://github.com/friendly-bits/geoip-shell.git "$GEOIP_SHELL_DIR" \
        || die "Falha ao clonar geoip-shell. Verifique a conexão com o GitHub."

    info "geoip-shell clonado em $GEOIP_SHELL_DIR"
}

# ═══════════════════════════════════════════════════════════
# WIZARD INTERATIVO
# ═══════════════════════════════════════════════════════════

wizard() {
    echo ""
    echo -e "${BLUE}${BOLD}============================================${NC}"
    echo -e "${BLUE}${BOLD}   GeoIP Firewall — Configuração Inicial    ${NC}"
    echo -e "${BLUE}${BOLD}   AMS SOFT (www.amssoft.com.br)                 ${NC}"
    echo -e "${BLUE}${BOLD}============================================${NC}"
    echo ""

    # ── Pergunta 1: Modo ──────────────────────────────────
    header "[1/3] Modo de operação:"
    echo "  1) Whitelist — permite APENAS os países selecionados ${CYAN}(recomendado)${NC}"
    echo "  2) Blacklist — bloqueia APENAS os países selecionados"
    echo ""
    ask "Escolha [1]: "
    read -r MODE_CHOICE
    MODE_CHOICE="${MODE_CHOICE:-1}"

    case "$MODE_CHOICE" in
        1) GEOIP_MODE="whitelist" ;;
        2) GEOIP_MODE="blacklist" ;;
        *) warn "Opção inválida, usando whitelist."; GEOIP_MODE="whitelist" ;;
    esac
    info "Modo: ${BOLD}$GEOIP_MODE${NC}"

    # ── Pergunta 2: Países/Regiões ────────────────────────
    header "[2/3] Quais países/regiões?"
    echo "  1) Somente Brasil                       (BR)"
    echo "  2) América do Sul                       (BR AR UY PY BO PE CL CO VE EC ...)"
    echo "  3) MERCOSUL                             (BR AR UY PY)"
    echo "  4) América Latina                       (BR AR + América Central + MX)"
    echo "  5) Brasil + Portugal                    (BR PT)"
    echo "  6) Mundo Lusófono                       (BR PT AO MZ CV ST GW TL MO)"
    echo "  7) Europa                               (todos os países europeus)"
    echo "  8) América do Norte                     (US CA MX)"
    echo "  9) AMS SOFT Blacklist                   (bloquear bots: CN RU IN VN ID BD PK ...)"
    echo "  0) Personalizado                        (digitar códigos ISO manualmente)"
    echo ""
    ask "Escolha [1]: "
    read -r REGION_CHOICE
    REGION_CHOICE="${REGION_CHOICE:-1}"

    case "$REGION_CHOICE" in
        1) COUNTRIES="${PRESETS[brazil_only]}" ;;
        2) COUNTRIES="${PRESETS[south_america]}" ;;
        3) COUNTRIES="${PRESETS[mercosul]}" ;;
        4) COUNTRIES="${PRESETS[latin_america]}" ;;
        5) COUNTRIES="${PRESETS[brazil_portugal]}" ;;
        6) COUNTRIES="${PRESETS[portuguese_world]}" ;;
        7) COUNTRIES="${PRESETS[europe]}" ;;
        8) COUNTRIES="${PRESETS[north_america]}" ;;
        9) COUNTRIES="${PRESETS[amssoft_blacklist]}" ;;
        0)
            echo ""
            ask "Digite os códigos ISO separados por espaço (ex: BR AR US):"
            read -r COUNTRIES
            COUNTRIES="${COUNTRIES^^}"
            ;;
        *) warn "Opção inválida, usando Brasil."; COUNTRIES="${PRESETS[brazil_only]}" ;;
    esac
    info "Países configurados: ${BOLD}$(format_countries "$COUNTRIES")${NC}"

    # ── Pergunta 3: Interface ─────────────────────────────
    detect_interface
    header "[3/3] Interface de rede:"
    echo "  Auto-detectada: ${BOLD}$DETECTED_IF${NC}"
    echo ""
    ask "Pressione ENTER para confirmar ou digite outra interface: "
    read -r IF_INPUT
    NETWORK_IF="${IF_INPUT:-$DETECTED_IF}"
    info "Interface: ${BOLD}$NETWORK_IF${NC}"

    # ── Whitelist adicional ───────────────────────────────
    header "[Opcional] IPs adicionais para whitelist:"
    echo "  Use para liberar IPs de países bloqueados (ex: servidores externos, clientes, etc.)"
    echo "  Formato: IP ou range CIDR — ex: 65.21.100.50 ou 95.216.0.0/16"
    echo ""

    EXTRA_WHITELIST=()
    EXTRA_LABELS=()

    while true; do
        ask "IP ou range para whitelist (ENTER para pular/terminar): "
        read -r WL_IP
        [[ -z "$WL_IP" ]] && break

        ask "Label/descrição para este IP (opcional): "
        read -r WL_LABEL
        WL_LABEL="${WL_LABEL:-sem descrição}"

        EXTRA_WHITELIST+=("$WL_IP")
        EXTRA_LABELS+=("$WL_LABEL")
        info "Adicionado: $WL_IP — $WL_LABEL"
    done
}

# ═══════════════════════════════════════════════════════════
# GERAR ARQUIVOS DE CONFIGURAÇÃO
# ═══════════════════════════════════════════════════════════

generate_configs() {
    step "Gerando arquivos de configuração"

    mkdir -p "$CONF_DIR"
    touch "$LOG_FILE"

    # ── config.conf ───────────────────────────────────────
    cat > "$CONF_FILE" << EOF
# ============================================================
#  GeoIP Firewall — Configuração Principal
#  AMS SOFT (www.amssoft.com.br)
#  Gerado em: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

# Modo de operação:
#   whitelist = permite APENAS os países listados em COUNTRIES
#   blacklist = bloqueia APENAS os países listados em COUNTRIES
MODE="$GEOIP_MODE"

# Países ativos (códigos ISO 3166-1 alpha-2, separados por espaço)
# Para adicionar: geoip-fw add-country XX
# Para remover:   geoip-fw remove-country XX
COUNTRIES="$COUNTRIES"

# Interface de rede alvo
INTERFACE="$NETWORK_IF"

# Ação para IPs bloqueados: DROP (silencioso) ou REJECT (retorna erro)
BLOCK_ACTION="DROP"

# Manter redes privadas sempre na whitelist (recomendado: yes)
ALLOW_PRIVATE="yes"

# Habilitar log de bloqueios (yes/no)
ENABLE_LOG="yes"
LOG_PREFIX="[GEOIP-BLOCK] "

# Intervalo de atualização das listas em dias
UPDATE_INTERVAL="7"

# Fonte das listas de IPs: ripe ou ipdeny
IP_SOURCE="ripe"

# Famílias de IP ativas: ipv4, ipv6 ou "ipv4 ipv6"
IP_FAMILIES="ipv4 ipv6"
EOF

    info "config.conf gerado em $CONF_FILE"

    # ── whitelist.conf ────────────────────────────────────
    cat > "$WHITELIST_FILE" << EOF
# ============================================================
#  GeoIP Firewall — Whitelist de IPs/Ranges
#  AMS SOFT (www.amssoft.com.br)
#
#  Formato: IP_OU_RANGE|tipo|descrição
#  Tipos: auto (sistema), manual (usuário), session (temporário)
#
#  Para gerenciar via CLI:
#    geoip-fw whitelist add 65.21.100.50 "Servidor Backup"
#    geoip-fw whitelist remove 65.21.100.50
#    geoip-fw whitelist list
# ============================================================

# Redes privadas RFC1918 (sempre permitidas)
10.0.0.0/8|auto|Rede privada RFC1918
172.16.0.0/12|auto|Rede privada RFC1918
192.168.0.0/16|auto|Rede privada RFC1918
127.0.0.0/8|auto|Loopback
EOF

    # Adicionar IP da sessão SSH
    detect_ssh_ip
    if [[ -n "$SSH_CLIENT_IP" ]]; then
        echo "${SSH_CLIENT_IP}|session|SSH session atual (temporário — removido no próximo reload)" >> "$WHITELIST_FILE"
        info "IP da sessão SSH adicionado à whitelist: $SSH_CLIENT_IP"
    fi

    # Adicionar IPs extras informados no wizard
    for i in "${!EXTRA_WHITELIST[@]}"; do
        echo "${EXTRA_WHITELIST[$i]}|manual|${EXTRA_LABELS[$i]}" >> "$WHITELIST_FILE"
        info "IP na whitelist: ${EXTRA_WHITELIST[$i]} — ${EXTRA_LABELS[$i]}"
    done

    info "whitelist.conf gerado em $WHITELIST_FILE"

    # ── domains.conf ──────────────────────────────────────
    if [[ ! -f "$DOMAINS_FILE" ]]; then
        cat > "$DOMAINS_FILE" << 'DOMAINS_EOF'
# ============================================================
#  GeoIP Firewall — Domínios para whitelist automática
#  AMS SOFT (www.amssoft.com.br)
#
#  Formato: domínio|descrição
#  Para gerenciar via CLI:
#    geoip-fw domain add api.exemplo.com "Gateway XYZ"
#    geoip-fw domain remove api.exemplo.com
#    geoip-fw domain list
#    geoip-fw domain sync   (força re-resolução)
# ============================================================

# ── Gateways de pagamento brasileiros e internacionais ────
api.mercadopago.com|MercadoPago — callback/IPN
elb-tl-mercadopago-1-520111085.us-east-1.elb.amazonaws.com|MercadoPago — ELB webhook us-east-1
ipnpb.paypal.com|PayPal — IPN
api.stripe.com|Stripe — webhooks
ws.pagseguro.uol.com.br|PagSeguro — notificações
api.cielo.com.br|Cielo — API pagamentos
api.gerencianet.com.br|Gerencianet/Efí — callback
api.efipay.com.br|Efí Pay — callback
api.asaas.com|Asaas — webhook
api.iugu.com|iugu — callback
api.pagar.me|Pagar.me — webhook
api.userede.com.br|Rede — API pagamentos
checkout.hotmart.com|Hotmart — notificação de venda
api.appmax.com.br|Appmax — webhook

# ── WHMCS — Licenciamento e núcleo ───────────────────────
a.licensing.whmcs.com|WHMCS — validação de licença (semanal)
releases.whmcs.com|WHMCS — verificação de atualizações

# ── Registradores de domínio ──────────────────────────────
api.namecheap.com|Namecheap — registro de domínios
api.enom.com|eNom — registro de domínios
rr-n1-tor.opensrs.net|OpenSRS — registro de domínios
api.internet.bs|Internet.bs — registro de domínios
api.resellerclub.com|ResellerClub/LogicBoxes — registro de domínios

# ── Proteção antifraude ───────────────────────────────────
minfraud.maxmind.com|MaxMind minFraud — pontuação antifraude

# ── Hospedagem / Painel de controle ──────────────────────
a.licensing.cpanel.net|cPanel — validação de licença
verify.cpanel.net|cPanel — verificação de licença
DOMAINS_EOF
        info "domains.conf gerado em $DOMAINS_FILE"
    else
        info "domains.conf já existe em $DOMAINS_FILE (preservando)"
    fi

    # ── cidr-sources.conf ─────────────────────────────────
    if [[ ! -f "$CIDR_SOURCES_FILE" ]]; then
        cat > "$CIDR_SOURCES_FILE" << 'CIDR_EOF'
# ============================================================
#  GeoIP Firewall — Fontes de CIDR confiáveis por URL
#  AMS SOFT (www.amssoft.com.br)
#
#  Formato: url|descrição
#  A URL deve retornar texto plano com um IP/CIDR por linha.
#
#  Para gerenciar via CLI:
#    geoip-fw cidr add https://example.com/ips "CDN XYZ"
#    geoip-fw cidr remove https://example.com/ips
#    geoip-fw cidr list
#    geoip-fw cidr sync   (força re-download)
# ============================================================

# ── CDNs / Infraestrutura confiável ──────────────────────
# Texto puro (auto-detectado):
https://www.cloudflare.com/ips-v4|Cloudflare IPv4 — CDN (Stripe, MercadoPago, APIs)
https://www.cloudflare.com/ips-v6|Cloudflare IPv6 — CDN (Stripe, MercadoPago, APIs)
# JSON (auto-detectado — extrai todos os CIDRs automaticamente):
https://api.fastly.com/public-ip-list|Fastly — CDN (GitHub, npm, SaaS)
# JSON com filtro explícito (3º campo = filtro jq):
https://ip-ranges.amazonaws.com/ip-ranges.json|AWS CloudFront + SES + S3|.prefixes[],.ipv6_prefixes[] | select(.service=="CLOUDFRONT" or .service=="SES" or .service=="S3") | .ip_prefix // .ipv6_prefix
https://www.gstatic.com/ipranges/cloud.json|Google Cloud (Firebase, OAuth, APIs)|.prefixes[] | .ipv4Prefix // .ipv6Prefix
https://api.github.com/meta|GitHub (Webhooks, API)|.web[],.api[],.hooks[]
https://docs.oracle.com/en-us/iaas/tools/public_ip_ranges.json|Oracle Cloud (OCI)|.regions[].cidrs[].cidr
CIDR_EOF
        info "cidr-sources.conf gerado em $CIDR_SOURCES_FILE"
    else
        info "cidr-sources.conf já existe em $CIDR_SOURCES_FILE (verificando novas fontes padrão...)"
        local default_cidr_sources=(
            "https://www.cloudflare.com/ips-v4|Cloudflare IPv4 — CDN (Stripe, MercadoPago, APIs)"
            "https://www.cloudflare.com/ips-v6|Cloudflare IPv6 — CDN (Stripe, MercadoPago, APIs)"
            "https://api.fastly.com/public-ip-list|Fastly — CDN (GitHub, npm, SaaS)"
            'https://ip-ranges.amazonaws.com/ip-ranges.json|AWS CloudFront + SES + S3|.prefixes[],.ipv6_prefixes[] | select(.service=="CLOUDFRONT" or .service=="SES" or .service=="S3") | .ip_prefix // .ipv6_prefix'
            'https://www.gstatic.com/ipranges/cloud.json|Google Cloud (Firebase, OAuth, APIs)|.prefixes[] | .ipv4Prefix // .ipv6Prefix'
            'https://api.github.com/meta|GitHub (Webhooks, API)|.web[],.api[],.hooks[]'
            'https://docs.oracle.com/en-us/iaas/tools/public_ip_ranges.json|Oracle Cloud (OCI)|.regions[].cidrs[].cidr'
        )
        local _added_cidr=0
        for _src in "${default_cidr_sources[@]}"; do
            local _url
            _url=$(echo "$_src" | cut -d'|' -f1)
            if ! grep -qF "$_url" "$CIDR_SOURCES_FILE" 2>/dev/null; then
                echo "$_src" >> "$CIDR_SOURCES_FILE"
                info "  Nova fonte CIDR adicionada: $_url"
                _added_cidr=$((_added_cidr + 1))
            elif ! grep -qF "$_src" "$CIDR_SOURCES_FILE" 2>/dev/null; then
                sed -i "\|${_url}|d" "$CIDR_SOURCES_FILE"
                echo "$_src" >> "$CIDR_SOURCES_FILE"
                info "  Fonte CIDR atualizada: $_url"
                _added_cidr=$((_added_cidr + 1))
            fi
        done
        [[ $_added_cidr -gt 0 ]] && info "$_added_cidr fonte(s) CIDR adicionada(s)/atualizada(s) ao cidr-sources.conf."
    fi
}

# ═══════════════════════════════════════════════════════════
# INSTALAR WRAPPER geoip-fw
# ═══════════════════════════════════════════════════════════

install_wrapper() {
    step "Instalando wrapper geoip-fw"

    cat > "$WRAPPER_BIN" << 'WRAPPER_EOF'
#!/usr/bin/env bash
# ============================================================
#  geoip-fw — Wrapper CLI para GeoIP Firewall
#  AMS SOFT (www.amssoft.com.br)
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

CONF_DIR="/etc/geoip-firewall"
CONF_FILE="$CONF_DIR/config.conf"
WHITELIST_FILE="$CONF_DIR/whitelist.conf"
DOMAINS_FILE="$CONF_DIR/domains.conf"
CIDR_SOURCES_FILE="$CONF_DIR/cidr-sources.conf"
WRAPPER_BIN="/usr/local/bin/geoip-fw"
LOG_FILE="/var/log/geoip-firewall.log"
GEOIP_SHELL_DIR="/opt/geoip-shell"

info()  { echo -e "${GREEN}✔${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
error() { echo -e "${RED}✖${NC} $*"; }
die()   { error "$*"; exit 1; }

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null || true; }

# ── Presets ───────────────────────────────────────────────
declare -A PRESETS
PRESETS[brazil_only]="BR"
PRESETS[south_america]="BR AR UY PY BO PE CL CO VE EC GY SR GF FK"
PRESETS[mercosul]="BR AR UY PY"
PRESETS[latin_america]="BR AR UY PY BO PE CL CO VE EC MX GT BZ HN SV NI CR PA CU DO HT JM TT BB"
PRESETS[brazil_portugal]="BR PT"
PRESETS[europe]="AL AD AT BE BA BG HR CY CZ DK EE FI FR DE GR HU IS IE IT LV LI LT LU MT ME NL MK NO PL PT RO RS SK SI ES SE CH GB"
PRESETS[north_america]="US CA MX"
PRESETS[portuguese_world]="BR PT AO MZ CV ST GW TL MO"

# Países fora das Américas com alto risco de bots e sem relação comercial com a AMS SOFT.
# Uso: geoip-fw add-continent amssoft_blacklist (no modo blacklist)
PRESETS[amssoft_blacklist]="CN RU IN VN ID BD PK EG NG TR IQ IR AF MM KH LA NP LK TH PH MY TW HK KZ UZ SA AE KW QA BH OM JO LB SY YE SD LY DZ TN MA KE GH SN ET TZ UG ZA MG JP KR"

# ─── Nomes dos países (ISO 3166-1 alpha-2 → pt-BR) ─────────
declare -A COUNTRY_NAMES=(
    [AD]="Andorra" [AE]="Emirados Árabes" [AF]="Afeganistão" [AG]="Antígua e Barbuda"
    [AL]="Albânia" [AM]="Armênia" [AO]="Angola" [AR]="Argentina" [AT]="Áustria"
    [AU]="Austrália" [AZ]="Azerbaijão" [BA]="Bósnia e Herzegovina" [BB]="Barbados"
    [BD]="Bangladesh" [BE]="Bélgica" [BF]="Burkina Faso" [BG]="Bulgária" [BH]="Bahrein"
    [BI]="Burundi" [BJ]="Benin" [BN]="Brunei" [BO]="Bolívia" [BR]="Brasil"
    [BS]="Bahamas" [BT]="Butão" [BW]="Botsuana" [BY]="Bielorrússia" [BZ]="Belize"
    [CA]="Canadá" [CD]="Congo (RDC)" [CF]="Rep. Centro-Africana" [CG]="Congo"
    [CH]="Suíça" [CI]="Costa do Marfim" [CL]="Chile" [CM]="Camarões" [CN]="China"
    [CO]="Colômbia" [CR]="Costa Rica" [CU]="Cuba" [CV]="Cabo Verde" [CY]="Chipre"
    [CZ]="Tchéquia" [DE]="Alemanha" [DJ]="Djibuti" [DK]="Dinamarca" [DM]="Dominica"
    [DO]="Rep. Dominicana" [DZ]="Argélia" [EC]="Equador" [EE]="Estônia" [EG]="Egito"
    [ER]="Eritreia" [ES]="Espanha" [ET]="Etiópia" [FI]="Finlândia" [FJ]="Fiji"
    [FM]="Micronésia" [FR]="França" [GA]="Gabão" [GB]="Reino Unido" [GD]="Granada"
    [GE]="Geórgia" [GF]="Guiana Francesa" [GH]="Gana" [GM]="Gâmbia" [GN]="Guiné"
    [GQ]="Guiné Equatorial" [GR]="Grécia" [GT]="Guatemala" [GW]="Guiné-Bissau"
    [GY]="Guiana" [HN]="Honduras" [HR]="Croácia" [HT]="Haiti" [HU]="Hungria"
    [ID]="Indonésia" [IE]="Irlanda" [IL]="Israel" [IN]="Índia" [IQ]="Iraque"
    [IR]="Irã" [IS]="Islândia" [IT]="Itália" [JM]="Jamaica" [JO]="Jordânia"
    [JP]="Japão" [KE]="Quênia" [KG]="Quirguistão" [KH]="Camboja" [KI]="Kiribati"
    [KM]="Comores" [KN]="São Cristóvão e Nevis" [KP]="Coreia do Norte"
    [KR]="Coreia do Sul" [KW]="Kuwait" [KZ]="Cazaquistão" [LA]="Laos" [LB]="Líbano"
    [LC]="Santa Lúcia" [LI]="Liechtenstein" [LK]="Sri Lanka" [LR]="Libéria"
    [LS]="Lesoto" [LT]="Lituânia" [LU]="Luxemburgo" [LV]="Letônia" [LY]="Líbia"
    [MA]="Marrocos" [MC]="Mônaco" [MD]="Moldávia" [ME]="Montenegro" [MG]="Madagascar"
    [MK]="Macedônia do Norte" [ML]="Mali" [MM]="Mianmar" [MN]="Mongólia"
    [MR]="Mauritânia" [MT]="Malta" [MU]="Maurício" [MV]="Maldivas" [MW]="Malawi"
    [MX]="México" [MY]="Malásia" [MZ]="Moçambique" [NA]="Namíbia" [NE]="Níger"
    [NG]="Nigéria" [NI]="Nicarágua" [NL]="Holanda" [NO]="Noruega" [NP]="Nepal"
    [NR]="Nauru" [NZ]="Nova Zelândia" [OM]="Omã" [PA]="Panamá" [PE]="Peru"
    [PG]="Papua-Nova Guiné" [PH]="Filipinas" [PK]="Paquistão" [PL]="Polônia"
    [PT]="Portugal" [PW]="Palau" [PY]="Paraguai" [QA]="Catar" [RO]="Romênia"
    [RS]="Sérvia" [RU]="Rússia" [RW]="Ruanda" [SA]="Arábia Saudita"
    [SB]="Ilhas Salomão" [SC]="Seicheles" [SD]="Sudão" [SE]="Suécia"
    [SG]="Singapura" [SI]="Eslovênia" [SK]="Eslováquia" [SL]="Serra Leoa"
    [SM]="San Marino" [SN]="Senegal" [SO]="Somália" [SR]="Suriname"
    [SS]="Sudão do Sul" [ST]="São Tomé e Príncipe" [SV]="El Salvador"
    [SY]="Síria" [SZ]="Essuatini" [TD]="Chade" [TG]="Togo" [TH]="Tailândia"
    [TJ]="Tajiquistão" [TL]="Timor-Leste" [TM]="Turcomenistão" [TN]="Tunísia"
    [TO]="Tonga" [TR]="Turquia" [TT]="Trinidad e Tobago" [TV]="Tuvalu"
    [TW]="Taiwan" [TZ]="Tanzânia" [UA]="Ucrânia" [UG]="Uganda" [US]="Estados Unidos"
    [UY]="Uruguai" [UZ]="Uzbequistão" [VA]="Vaticano" [VC]="São Vicente e Granadinas"
    [VE]="Venezuela" [VN]="Vietnã" [VU]="Vanuatu" [WS]="Samoa" [FK]="Ilhas Malvinas"
    [YE]="Iêmen" [ZA]="África do Sul" [ZM]="Zâmbia" [ZW]="Zimbábue" [MO]="Macau"
)

country_name() {
    local cc="${1^^}"
    echo "${COUNTRY_NAMES[$cc]:-$cc}"
}

format_countries() {
    local out="" cc
    for cc in $1; do
        out+="$cc ($(country_name "$cc")) "
    done
    echo "${out% }"
}

# ── Carregar config ───────────────────────────────────────
load_config() {
    [[ -f "$CONF_FILE" ]] || die "Configuração não encontrada: $CONF_FILE"
    # shellcheck source=/dev/null
    source "$CONF_FILE"
}

# ── Salvar lista de países no config ──────────────────────
save_countries() {
    local new_list="$1"
    sed -i "s|^COUNTRIES=.*|COUNTRIES=\"$new_list\"|" "$CONF_FILE"
}

# ── Aplicar regras via geoip-shell ────────────────────────
apply_rules() {
    load_config

    echo -e "\n${CYAN}► Aplicando regras GeoIP...${NC}"

    local gs_mode="$MODE"
    local gs_countries="$COUNTRIES"

    # IPs privados: em whitelist usa -l (LAN nativo), em blacklist vai para -t (trusted)
    local gs_lan_args=()
    local private_ranges="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/8 fd00::/8 fe80::/10"

    # IPs trusted do whitelist.conf → trusted (-t) do geoip-shell
    local gs_trusted_args=()
    local trusted_ips=""
    if [[ -f "$WHITELIST_FILE" ]]; then
        if [[ "$gs_mode" == "blacklist" ]]; then
            # Em blacklist, só manual e session (domínios/CIDRs são desnecessários)
            trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        else
            # Em whitelist, todos os tipos exceto auto (que vão para -l)
            trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session|domain|cidr)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        fi
    fi

    # Em blacklist, adicionar redes privadas à lista trusted (pois -l não é suportado)
    # Não deduplica: as entradas 'auto' no whitelist.conf são apenas documentação;
    # apply_rules() extrai só manual|session, então não há duplicata real
    if [[ "$gs_mode" == "blacklist" && "${ALLOW_PRIVATE:-yes}" == "yes" ]]; then
        trusted_ips="$private_ranges $trusted_ips"
    elif [[ "$gs_mode" == "whitelist" && "${ALLOW_PRIVATE:-yes}" == "yes" ]]; then
        gs_lan_args=(-l "$private_ranges")
    fi

    [[ -n "$trusted_ips" ]] && gs_trusted_args=(-t "$trusted_ips")

    # Atualizar o config do geoip-shell ANTES de chamar configure
    # (evita conflito com config salva antiga)
    local gs_conf="/etc/geoip-shell/geoip-shell.conf"
    if [[ -f "$gs_conf" ]]; then
        sed -i "s|^inbound_geomode=.*|inbound_geomode=$gs_mode|" "$gs_conf"
        # Em blacklist, limpar lan_ips (pois vamos usar trusted)
        if [[ "$gs_mode" == "blacklist" ]]; then
            sed -i "s|^lan_ips_ipv4=.*|lan_ips_ipv4=|" "$gs_conf"
            sed -i "s|^lan_ips_ipv6=.*|lan_ips_ipv6=|" "$gs_conf"
        fi
    fi

    if command -v geoip-shell &>/dev/null; then
        geoip-shell configure -z \
            -m "$gs_mode" \
            -c "$gs_countries" \
            -i "$INTERFACE" \
            -u "$IP_SOURCE" \
            -f "${IP_FAMILIES:-ipv4 ipv6}" \
            "${gs_lan_args[@]}" \
            "${gs_trusted_args[@]}" \
            2>&1 | tail -5
    else
        die "geoip-shell não encontrado. Execute o instalador novamente."
    fi

    log "Regras aplicadas: modo=$gs_mode países=$gs_countries"
    info "Regras aplicadas com sucesso."
}

# ── STATUS ────────────────────────────────────────────────
cmd_status() {
    load_config
    echo ""
    echo -e "${BOLD}═══ GeoIP Firewall — Status ═══${NC}"
    echo -e "  Modo:        ${CYAN}${MODE}${NC}"
    echo -e "  Interface:   ${CYAN}${INTERFACE}${NC}"
    echo -e "  Países:      ${CYAN}$(format_countries "$COUNTRIES")${NC}"
    echo -e "  Log:         ${CYAN}${LOG_FILE}${NC}"
    echo ""

    if command -v geoip-shell &>/dev/null; then
        echo -e "${BOLD}── geoip-shell status ──${NC}"
        geoip-shell status 2>/dev/null || warn "geoip-shell status indisponível"
    fi

    echo ""
    echo -e "${BOLD}── Whitelist ──${NC}"
    cmd_whitelist_list_quiet
    echo ""
}

# ── ADD-COUNTRY ───────────────────────────────────────────
cmd_add_country() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw add-country <CC> [CC2 CC3...]"
    load_config

    local added=()
    for cc in "$@"; do
        cc="${cc^^}"
        if echo "$COUNTRIES" | grep -qw "$cc"; then
            warn "$cc ($(country_name "$cc")) já está na lista."
        else
            COUNTRIES="$COUNTRIES $cc"
            added+=("$cc")
        fi
    done

    COUNTRIES=$(echo "$COUNTRIES" | xargs)
    save_countries "$COUNTRIES"

    for cc in "${added[@]}"; do
        info "País adicionado: $cc — $(country_name "$cc")"
    done

    echo ""
    echo -e "${YELLOW}Para aplicar as mudanças execute:${NC} geoip-fw reload"
}

# ── REMOVE-COUNTRY ────────────────────────────────────────
cmd_remove_country() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw remove-country <CC> [CC2 CC3...]"
    load_config

    for cc in "$@"; do
        cc="${cc^^}"
        if ! echo "$COUNTRIES" | grep -qw "$cc"; then
            warn "$cc ($(country_name "$cc")) não está na lista."
            continue
        fi
        COUNTRIES=$(echo "$COUNTRIES" | tr ' ' '\n' | grep -v "^${cc}$" | tr '\n' ' ' | xargs)
        info "País removido: $cc — $(country_name "$cc")"
    done

    save_countries "$COUNTRIES"
    echo ""
    echo -e "${YELLOW}Para aplicar as mudanças execute:${NC} geoip-fw reload"
}

# ── ADD-CONTINENT ─────────────────────────────────────────
cmd_add_continent() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw add-continent <preset>"
    local preset="${1,,}"

    [[ -v "PRESETS[$preset]" ]] || {
        error "Preset '$preset' não encontrado."
        echo "  Presets disponíveis: ${!PRESETS[*]}"
        exit 1
    }

    load_config
    local new_countries="${PRESETS[$preset]}"
    local added=0
    local added_list=""

    for cc in $new_countries; do
        if ! echo "$COUNTRIES" | grep -qw "$cc"; then
            COUNTRIES="$COUNTRIES $cc"
            added_list+="$cc ($(country_name "$cc")) "
            ((added++))
        fi
    done

    COUNTRIES=$(echo "$COUNTRIES" | xargs)
    save_countries "$COUNTRIES"
    info "Preset '$preset' adicionado ($added países novos)."
    [[ -n "$added_list" ]] && echo -e "   Novos: ${added_list% }"
    echo ""
    echo -e "${YELLOW}Para aplicar as mudanças execute:${NC} geoip-fw reload"
}

# ── WHITELIST ADD ─────────────────────────────────────────
cmd_whitelist_add() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw whitelist add <IP/CIDR> [\"descrição\"]"

    local ip_range="$1"
    local label="${2:-sem descrição}"

    # Validação básica de IP/CIDR
    if ! echo "$ip_range" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$'; then
        die "Formato inválido: $ip_range. Use IP (ex: 1.2.3.4) ou CIDR (ex: 1.2.3.0/24)"
    fi

    # Checar duplicata
    if grep -q "^${ip_range}|" "$WHITELIST_FILE" 2>/dev/null; then
        warn "$ip_range já está na whitelist."
        return 0
    fi

    echo "${ip_range}|manual|${label}" >> "$WHITELIST_FILE"
    info "Adicionado à whitelist: $ip_range — $label"

    # Aplicar imediatamente via geoip-shell trusted (-t)
    if command -v geoip-shell &>/dev/null; then
        local trusted_ips
        load_config 2>/dev/null || true
        if [[ "${MODE:-whitelist}" == "blacklist" ]]; then
            trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        else
            trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session|domain|cidr)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        fi
        [[ -n "$trusted_ips" ]] && geoip-shell configure -z -t "$trusted_ips" &>/dev/null && info "Regra ativa imediatamente." || true
    fi

    log "Whitelist add: $ip_range — $label"
}

# ── WHITELIST REMOVE ──────────────────────────────────────
cmd_whitelist_remove() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw whitelist remove <IP/CIDR>"

    local ip_range="$1"

    if ! grep -q "^${ip_range}|" "$WHITELIST_FILE" 2>/dev/null; then
        warn "$ip_range não encontrado na whitelist."
        return 0
    fi

    # Impedir remoção de IPs auto (RFC1918)
    if grep -q "^${ip_range}|auto|" "$WHITELIST_FILE"; then
        die "Não é possível remover entradas automáticas (RFC1918/loopback). Edite $WHITELIST_FILE manualmente se necessário."
    fi

    sed -i "/^${ip_range}|/d" "$WHITELIST_FILE"
    info "Removido da whitelist: $ip_range"

    # Atualizar trusted IPs no geoip-shell imediatamente
    if command -v geoip-shell &>/dev/null; then
        local trusted_ips
        load_config 2>/dev/null || true
        if [[ "${MODE:-whitelist}" == "blacklist" ]]; then
            trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        else
            trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session|domain|cidr)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        fi
        if [[ -n "$trusted_ips" ]]; then
            geoip-shell configure -z -t "$trusted_ips" &>/dev/null || true
        else
            geoip-shell configure -z -t none &>/dev/null || true
        fi
    fi

    log "Whitelist remove: $ip_range"
}

# ── WHITELIST LIST ────────────────────────────────────────
cmd_whitelist_list() {
    echo ""
    echo -e "${BOLD}═══ Whitelist Atual ═══${NC}"
    cmd_whitelist_list_quiet
    echo ""
}

cmd_whitelist_list_quiet() {
    local count=0
    while IFS='|' read -r ip_range type label || [[ -n "$ip_range" ]]; do
        [[ "$ip_range" =~ ^#.*$ || -z "$ip_range" ]] && continue
        case "$type" in
            auto)    echo -e "  ${GREEN}[auto]${NC}    $(printf '%-22s' "$ip_range") $label" ;;
            manual)  echo -e "  ${CYAN}[manual]${NC}  $(printf '%-22s' "$ip_range") $label" ;;
            session) echo -e "  ${YELLOW}[session]${NC} $(printf '%-22s' "$ip_range") $label" ;;
            domain)  echo -e "  \033[0;35m[domain]${NC}  $(printf '%-22s' "$ip_range") $label" ;;
            cidr)    echo -e "  \033[0;34m[cidr]${NC}    $(printf '%-22s' "$ip_range") $label" ;;
        esac
        count=$((count + 1))
    done < "$WHITELIST_FILE"
    echo -e "  Total: $count entradas"
}

# ── RELOAD ────────────────────────────────────────────────
cmd_reload() {
    echo -e "\n${CYAN}► Removendo entradas de sessão antigas...${NC}"
    sed -i '/|session|/d' "$WHITELIST_FILE"

    apply_rules
    info "Reload concluído."
}

# ── FW STATUS (helper) ───────────────────────────────────
fw_status_brief() {
    if iptables -t mangle -L GEOIP-SHELL_IN -n 2>/dev/null | grep "DROP\|ACCEPT" >/dev/null 2>&1; then
        echo "active"
    elif crontab -l 2>/dev/null | grep -q "geoip-shell-persistence"; then
        echo "paused"
    else
        echo "disabled"
    fi
}

# ── PAUSE (temporário) ────────────────────────────────────
cmd_pause() {
    local status
    status=$(fw_status_brief)
    if [[ "$status" == "active" ]]; then
        geoip-shell stop 2>/dev/null || true
        info "Firewall PAUSADO. Todo tráfego liberado temporariamente."
        warn "As regras voltam automaticamente no próximo reboot."
        warn "Para reativar agora: geoip-fw enable"
        log "Firewall pausado manualmente."
    else
        warn "Firewall já está $( [[ "$status" == "paused" ]] && echo 'pausado' || echo 'desativado' )."
    fi
}

# ── ENABLE (reativar) ─────────────────────────────────────
cmd_enable() {
    echo -e "\n${CYAN}► Reativando GeoIP Firewall...${NC}"

    # Restaurar persistence cron se foi removido
    if ! crontab -l 2>/dev/null | grep -q "geoip-shell-persistence"; then
        ( crontab -l 2>/dev/null
          echo "@reboot /usr/bin/geoip-shell-run.sh restore -a 1>/dev/null 2>/dev/null # geoip-shell-persistence"
        ) | crontab -
        info "Persistência no boot restaurada."
    fi

    apply_rules
    info "Firewall REATIVADO com sucesso."
    log "Firewall reativado manualmente."
}

# ── DISABLE (permanente) ─────────────────────────────────
cmd_disable() {
    echo ""
    echo -e "${RED}${BOLD}ATENÇÃO: O firewall será desativado permanentemente.${NC}"
    echo -e "${YELLOW}Todo tráfego ficará liberado até você reativar manualmente.${NC}"
    echo -n "Confirmar desativação? [s/N]: "
    read -r confirm
    [[ "${confirm,,}" != "s" ]] && { echo "Cancelado."; return 0; }

    # Parar regras
    geoip-shell stop 2>/dev/null || true

    # Remover persistence cron (@reboot)
    if crontab -l 2>/dev/null | grep -q "geoip-shell-persistence"; then
        crontab -l 2>/dev/null | grep -v "geoip-shell-persistence" | crontab -
        info "Persistência no boot removida."
    fi

    warn "Firewall DESATIVADO. Execute 'geoip-fw enable' para reativar."
    log "Firewall desativado permanentemente."
}

# ── UPDATE ────────────────────────────────────────────────
cmd_update() {
    echo -e "\n${CYAN}► Forçando atualização das listas GeoIP...${NC}"
    if command -v geoip-shell-run.sh &>/dev/null; then
        geoip-shell-run.sh update
    elif [[ -x /usr/bin/geoip-shell-run.sh ]]; then
        /usr/bin/geoip-shell-run.sh update
    else
        die "geoip-shell-run.sh não encontrado. Verifique a instalação do geoip-shell."
    fi
    info "Listas atualizadas."
    log "Listas GeoIP atualizadas manualmente."
}

# ── TEST-IP ───────────────────────────────────────────────
cmd_test_ip() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw test-ip <IP>"
    local ip="$1"

    echo -e "\n${BOLD}Verificando IP: $ip${NC}"

    # Checar se está na whitelist
    if grep -q "^${ip}|" "$WHITELIST_FILE" 2>/dev/null; then
        local label
        label=$(grep "^${ip}|" "$WHITELIST_FILE" | cut -d'|' -f3)
        info "IP está na whitelist: $label"
        return 0
    fi

    # Lookup via ipinfo.io
    local result
    result=$(curl -s --connect-timeout 5 "https://ipinfo.io/${ip}/json" 2>/dev/null || echo '{}')
    local country org
    country=$(echo "$result" | grep '"country"' | cut -d'"' -f4)
    org=$(echo "$result" | grep '"org"' | cut -d'"' -f4)

    if [[ -n "$country" ]]; then
        echo -e "  País:         ${CYAN}$country — $(country_name "$country")${NC}"
        echo -e "  Organização: ${CYAN}$org${NC}"

        load_config
        if echo "$COUNTRIES" | grep -qw "$country"; then
            if [[ "$MODE" == "whitelist" ]]; then
                info "Este IP seria PERMITIDO (país $country — $(country_name "$country") está na whitelist)"
            else
                warn "Este IP seria BLOQUEADO (país $country — $(country_name "$country") está na blacklist)"
            fi
        else
            if [[ "$MODE" == "whitelist" ]]; then
                warn "Este IP seria BLOQUEADO (país $country — $(country_name "$country") não está na whitelist)"
            else
                info "Este IP seria PERMITIDO (país $country — $(country_name "$country") não está na blacklist)"
            fi
        fi
    else
        warn "Não foi possível obter informações do IP $ip"
    fi
}

# ── UNINSTALL ─────────────────────────────────────────────
cmd_uninstall() {
    echo ""
    echo -e "${RED}${BOLD}ATENÇÃO: Isso removerá todas as regras GeoIP e os arquivos de configuração.${NC}"
    echo -n "Confirma a remoção? [s/N]: "
    read -r confirm
    [[ "${confirm,,}" != "s" ]] && { echo "Cancelado."; exit 0; }

    echo -e "\n${CYAN}► Removendo regras do firewall...${NC}"
    if command -v geoip-shell &>/dev/null; then
        geoip-shell stop 2>/dev/null || true
        bash "/opt/geoip-shell/geoip-shell-uninstall.sh" -f 2>/dev/null || true
    fi

    # Remover ipsets
    if command -v ipset &>/dev/null; then
        ipset destroy geoip-whitelist 2>/dev/null || true
    fi

    # Remover arquivos
    rm -rf "$CONF_DIR"
    rm -f "$WRAPPER_BIN"

    info "GeoIP Firewall removido com sucesso."
    echo -e "${YELLOW}Reinicie o servidor para garantir limpeza completa das regras.${NC}"
}

# ── CHECK / AUDITORIA COMPLETA ───────────────────────────
cmd_check() {
    load_config

    local issues=0
    local warnings=0

    _ok()   { echo -e "   ${GREEN}✔${NC} $(printf '%-22s' "$1") $2"; }
    _warn() { echo -e "   ${YELLOW}⚠${NC}  $(printf '%-22s' "$1") $2"; warnings=$((warnings + 1)); }
    _fail() { echo -e "   ${RED}✖${NC} $(printf '%-22s' "$1") $2"; issues=$((issues + 1)); }
    _sep()  { echo -e "\n   ${BOLD}[$1]${NC}"; }

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}   geoip-fw check — Auditoria Completa         ${NC}"
    echo -e "${BOLD}   $(date '+%Y-%m-%d %H:%M:%S')                ${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"

    # ────────────────────────────────────────────────
    _sep "SISTEMA"

    # geoip-shell instalado?
    if command -v geoip-shell &>/dev/null; then
        local gs_ver
        gs_ver=$(geoip-shell -V 2>/dev/null || echo "versão desconhecida")
        _ok "geoip-shell:" "$gs_ver"
    elif [[ -f "$GEOIP_SHELL_DIR/geoip-shell-install.sh" ]]; then
        _ok "geoip-shell:" "instalado em $GEOIP_SHELL_DIR"
    else
        _fail "geoip-shell:" "NÃO encontrado"
    fi

    # wrapper geoip-fw
    if [[ -x "$WRAPPER_BIN" ]]; then
        _ok "geoip-fw:" "$WRAPPER_BIN"
    else
        _fail "geoip-fw:" "NÃO encontrado em $WRAPPER_BIN"
    fi

    # config.conf
    if [[ -f "$CONF_FILE" ]]; then
        _ok "config.conf:" "$CONF_FILE"
    else
        _fail "config.conf:" "NÃO encontrado"
    fi

    # whitelist.conf
    if [[ -f "$WHITELIST_FILE" ]]; then
        local wl_count
        wl_count=$(grep -vc "^#\|^$" "$WHITELIST_FILE" 2>/dev/null || true); wl_count=${wl_count:-0}
        _ok "whitelist.conf:" "$wl_count entradas"
    else
        _warn "whitelist.conf:" "não encontrado"
    fi

    # Aviso sobre Let's Encrypt + GeoIP
    _warn "SSL Let's Encrypt:" "HTTP-01 bloqueado por GeoIP — use DNS-01 challenge no certbot/cPanel"

    # cron configurado?
    if [[ -f "/etc/cron.d/geoip-firewall" ]]; then
        local cron_sched
        cron_sched=$(grep -v "^#" /etc/cron.d/geoip-firewall 2>/dev/null | awk '{print $1,$2,$3,$4,$5}' | head -1)
        _ok "cron:" "$cron_sched"
    else
        _warn "cron:" "não configurado — atualizações automáticas desativadas"
    fi

    # última atualização das listas (lê do status file do geoip-shell)
    local last_update="desconhecida"
    local update_age_days=999
    local gs_status_file="/var/lib/geoip-shell/status"
    if [[ -f "$gs_status_file" ]]; then
        local last_update_str
        last_update_str=$(grep "^last_update=" "$gs_status_file" | cut -d= -f2-)
        if [[ -n "$last_update_str" ]]; then
            last_update="$last_update_str"
            local epoch_now epoch_update
            epoch_now=$(date +%s)
            epoch_update=$(date -d "$last_update_str" +%s 2>/dev/null || echo 0)
            [[ "$epoch_update" -gt 0 ]] && \
                update_age_days=$(( (epoch_now - epoch_update) / 86400 ))
        fi
    fi

    if [[ $update_age_days -le 7 ]]; then
        _ok "última atualização:" "$last_update (há ${update_age_days}d)"
    elif [[ $update_age_days -le 14 ]]; then
        _warn "última atualização:" "$last_update (há ${update_age_days}d — considere atualizar)"
    else
        _fail "última atualização:" "${last_update} (há ${update_age_days}d — DESATUALIZADO)"
    fi

    # ────────────────────────────────────────────────
    _sep "DADOS GEOIP"

    local stale_countries=()

    if [[ -f "$gs_status_file" ]]; then
        # Data geral de atualização
        local last_update_str
        last_update_str=$(grep "^last_update=" "$gs_status_file" | cut -d= -f2-)
        if [[ -n "$last_update_str" ]]; then
            local epoch_now epoch_update age_days
            epoch_now=$(date +%s)
            epoch_update=$(date -d "$last_update_str" +%s 2>/dev/null || echo 0)
            if [[ "$epoch_update" -gt 0 ]]; then
                age_days=$(( (epoch_now - epoch_update) / 86400 ))
                if [[ $age_days -le 3 ]]; then
                    _ok "atualização geral:" "$last_update_str (há ${age_days}d — recente)"
                elif [[ $age_days -le 7 ]]; then
                    _ok "atualização geral:" "$last_update_str (há ${age_days}d)"
                elif [[ $age_days -le 14 ]]; then
                    _warn "atualização geral:" "$last_update_str (há ${age_days}d — considere atualizar)"
                else
                    _fail "atualização geral:" "$last_update_str (há ${age_days}d — DESATUALIZADO)"
                fi
            fi
        fi

        # Tabela por país configurado
        echo ""
        printf "   ${BOLD}%-28s  %-12s  %8s  %8s${NC}\n" "PAÍS" "ÚLTIMA ATT" "IPv4" "IPv6"
        printf "   %-28s  %-12s  %8s  %8s\n"      "----------------------------" "------------" "--------" "--------"

        local cc
        for cc in $COUNTRIES; do
            local cc_date4 cc_date6 cc_cnt4 cc_cnt6 cc_label
            cc_date4=$(grep "^prev_date_${cc}_ipv4_ripe=" "$gs_status_file" 2>/dev/null | cut -d= -f2)
            cc_date6=$(grep "^prev_date_${cc}_ipv6_ripe=" "$gs_status_file" 2>/dev/null | cut -d= -f2)
            cc_cnt4=$(grep "^prev_ips_cnt_${cc}_ipv4_ripe=" "$gs_status_file" 2>/dev/null | cut -d= -f2)
            cc_cnt6=$(grep "^prev_ips_cnt_${cc}_ipv6_ripe=" "$gs_status_file" 2>/dev/null | cut -d= -f2)

            cc_date4="${cc_date4:-—}"
            cc_date6="${cc_date6:-—}"
            cc_cnt4="${cc_cnt4:-—}"
            cc_cnt6="${cc_cnt6:-—}"
            cc_label="$cc — $(country_name "$cc")"

            # Verificar se algum dos dois (IPv4/IPv6) está desatualizado
            local cc_stale=false
            for d in "$cc_date4" "$cc_date6"; do
                [[ "$d" == "—" ]] && continue
                local e_d
                e_d=$(date -d "$d" +%s 2>/dev/null || echo 0)
                if [[ "$e_d" -gt 0 ]]; then
                    local age_d=$(( (epoch_now - e_d) / 86400 ))
                    [[ $age_d -gt 14 ]] && cc_stale=true
                fi
            done

            if $cc_stale; then
                printf "   ${RED}%-28s  %-12s  %8s  %8s${NC}\n" "$cc_label" "$cc_date4" "$cc_cnt4" "$cc_cnt6"
                stale_countries+=("$cc — $(country_name "$cc")")
            else
                printf "   %-28s  %-12s  %8s  %8s\n" "$cc_label" "$cc_date4" "$cc_cnt4" "$cc_cnt6"
            fi
        done

        # Aviso final se há países desatualizados
        if [[ ${#stale_countries[@]} -gt 0 ]]; then
            echo ""
            _warn "países desatualizados:" "${stale_countries[*]}"
            echo -e "   ${YELLOW}   Execute ${BOLD}geoip-fw update${NC}${YELLOW} para baixar listas atualizadas antes de trocar o modo.${NC}"
        elif [[ $update_age_days -gt 7 ]]; then
            echo ""
            _warn "listas com mais de 7 dias:" "Execute ${BOLD}geoip-fw update${NC} para garantir dados precisos."
        else
            echo ""
            _ok "dados GeoIP:" "todos os países com dados recentes — seguro para trocar modo."
        fi
    else
        _warn "status do geoip-shell:" "arquivo $gs_status_file não encontrado"
        echo -e "   ${YELLOW}   Execute ${BOLD}geoip-fw update${NC}${YELLOW} para baixar as listas GeoIP.${NC}"
    fi

    # ────────────────────────────────────────────────
    _sep "FIREWALL"

    # Detectar backend ativo (geoip-shell usa GEOIP-SHELL_* em maiúsculas)
    local active_backend=""
    if nft list ruleset 2>/dev/null | grep -qi "geoip"; then
        active_backend="nftables/iptables-nft"
    elif iptables -t mangle -L 2>/dev/null | grep -qi "geoip" || \
         iptables -L 2>/dev/null | grep -qi "geoip"; then
        active_backend="iptables"
    fi

    if [[ -n "$active_backend" ]]; then
        _ok "backend:" "$active_backend (regras GeoIP detectadas)"
    else
        _warn "backend:" "regras GeoIP não detectadas no firewall ativo"
    fi

    # Modo e países
    _ok "modo:" "$MODE"
    local cc_count
    cc_count=$(echo "$COUNTRIES" | wc -w)
    _ok "países configurados:" "$cc_count — $(format_countries "$COUNTRIES")"

    # ipsets do geoip-shell — resumo por país (IPv4 + IPv6)
    if command -v ipset &>/dev/null; then
        local gs_sets
        gs_sets=$(ipset list -n 2>/dev/null | grep -c "^geoip-shell_[A-Z][A-Z]_") || gs_sets=0
        if [[ ${gs_sets:-0} -gt 0 ]]; then
            _ok "ipsets GeoIP:" "$gs_sets conjuntos carregados no kernel"
            echo ""
            printf "   ${BOLD}%-28s %10s %10s${NC}\n" "PAÍS" "IPv4" "IPv6"
            printf "   %-28s %10s %10s\n"              "----------------------------" "--------" "--------"
            local cc
            for cc in $(ipset list -n 2>/dev/null | grep -oE "geoip-shell_[A-Z]{2}_4_" | grep -oE "_[A-Z]{2}_" | tr -d '_' | sort -u); do
                local set4 set6 n4="-" n6="-"
                set4=$(ipset list -n 2>/dev/null | grep "geoip-shell_${cc}_4_" | head -1)
                set6=$(ipset list -n 2>/dev/null | grep "geoip-shell_${cc}_6_" | head -1)
                [[ -n "$set4" ]] && n4=$(ipset list "$set4" 2>/dev/null | awk '/Number of entries/{print $NF}')
                [[ -n "$set6" ]] && n6=$(ipset list "$set6" 2>/dev/null | awk '/Number of entries/{print $NF}')
                printf "   %-28s %10s %10s\n" "$cc — $(country_name "$cc")" "$n4" "$n6"
            done
            echo ""
        else
            _warn "ipsets GeoIP:" "nenhum ipset de país encontrado no kernel"
        fi
    fi

    # ────────────────────────────────────────────────
    _sep "TESTE DE IPs"

    # IP da sessão SSH — deve estar permitido
    local ssh_ip=""
    [[ -n "${SSH_CLIENT:-}" ]]     && ssh_ip=$(echo "$SSH_CLIENT"     | awk '{print $1}')
    [[ -n "${SSH_CONNECTION:-}" ]] && ssh_ip=$(echo "$SSH_CONNECTION" | awk '{print $1}')

    if [[ -n "$ssh_ip" ]]; then
        if grep -q "^${ssh_ip}|" "$WHITELIST_FILE" 2>/dev/null; then
            _ok "SSH session IP:" "$ssh_ip (na whitelist — ok)"
        else
            _warn "SSH session IP:" "$ssh_ip (NÃO está na whitelist — risco de perder acesso)"
        fi
    fi

    # Teste de IPs via lookup
    _check_ip_logic() {
        local ip="$1" expected="$2" label="$3"
        local result country org
        result=$(curl -s --connect-timeout 4 "https://ipinfo.io/${ip}/json" 2>/dev/null || echo '{}')
        country=$(echo "$result" | grep '"country"' | cut -d'"' -f4)
        org=$(echo "$result"     | grep '"org"'     | cut -d'"' -f4 | cut -c1-30)

        [[ -z "$country" ]] && { _warn "$label" "$ip (sem resposta do lookup)"; return; }

        local in_list=0
        echo "$COUNTRIES" | grep -qw "$country" && in_list=1

        local would_pass=0
        { [[ "$MODE" == "whitelist" && $in_list -eq 1 ]] || \
          [[ "$MODE" == "blacklist" && $in_list -eq 0 ]]; } && would_pass=1

        # whitelist manual tem prioridade
        grep -q "^${ip}|" "$WHITELIST_FILE" 2>/dev/null && would_pass=1

        if [[ "$expected" == "allow" && $would_pass -eq 1 ]]; then
            _ok "$label" "$ip ($country — $(country_name "$country") — $org) → PERMITIDO ✔"
        elif [[ "$expected" == "block" && $would_pass -eq 0 ]]; then
            _ok "$label" "$ip ($country — $(country_name "$country") — $org) → BLOQUEADO ✔"
        elif [[ "$expected" == "allow" && $would_pass -eq 0 ]]; then
            _fail "$label" "$ip ($country — $(country_name "$country")) → seria BLOQUEADO — verifique a config"
        else
            _fail "$label" "$ip ($country — $(country_name "$country")) → seria PERMITIDO — verifique a config"
        fi
    }

    # Testar IPs de referência conforme o modo
    if [[ "$MODE" == "whitelist" ]]; then
        # Pegar primeiro país da lista para testar IP permitido
        local first_cc
        first_cc=$(echo "$COUNTRIES" | awk '{print $1}')
        case "$first_cc" in
            BR) _check_ip_logic "177.75.0.1"  "allow" "IP teste ($first_cc — $(country_name "$first_cc")):" ;;
            AR) _check_ip_logic "190.220.0.1" "allow" "IP teste ($first_cc — $(country_name "$first_cc")):" ;;
            *)  _check_ip_logic "177.75.0.1"  "allow" "IP teste (BR — Brasil):" ;;
        esac
        # IP fora da lista deve ser bloqueado
        _check_ip_logic "8.8.8.8" "block" "IP teste (US — $(country_name "US")):"
    else
        # blacklist: IPs da lista devem ser bloqueados
        local first_cc
        first_cc=$(echo "$COUNTRIES" | awk '{print $1}')
        _check_ip_logic "8.8.8.8"    "allow" "IP teste (US — $(country_name "US")):"
        _check_ip_logic "177.75.0.1" "block" "IP teste ($first_cc — $(country_name "$first_cc")):"
    fi

    # ────────────────────────────────────────────────
    _sep "FAIL2BAN"

    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active fail2ban &>/dev/null 2>&1 || \
           fail2ban-client ping &>/dev/null 2>&1; then
            _ok "status:" "rodando"

            # Backend do fail2ban
            local fb_action
            fb_action=$(grep -rh "^banaction\s*=" /etc/fail2ban/jail.local \
                        /etc/fail2ban/jail.conf 2>/dev/null \
                        | head -1 | awk -F= '{print $2}' | xargs)
            local fb_backend="iptables"
            echo "$fb_action" | grep -qi "nftables" && fb_backend="nftables"

            # Verificar compatibilidade com o backend que o geoip-shell está usando
            if [[ "$fb_backend" == "${active_backend:-iptables}" ]]; then
                _ok "backend:" "$fb_backend (compatível com geoip ativo)"
            else
                _warn "backend:" "$fb_backend (pode conflitar com geoip usando ${active_backend:-iptables})"
            fi

            # Jails e IPs banidos
            local jail_list jail_count total_banned=0
            jail_list=$(fail2ban-client status 2>/dev/null \
                        | grep "Jail list" | sed 's/.*://;s/,//g' | xargs)
            jail_count=$(echo "$jail_list" | wc -w)
            _ok "jails ativos:" "$jail_count ($jail_list)"

            for jail in $jail_list; do
                local banned
                banned=$(fail2ban-client status "$jail" 2>/dev/null \
                         | grep "Currently banned" | awk '{print $NF}' || echo 0)
                total_banned=$(( total_banned + banned ))
            done
            _ok "IPs banidos agora:" "$total_banned"

            # Verificar erros recentes no log
            local fb_errors
            fb_errors=$(grep -c "ERROR" /var/log/fail2ban.log 2>/dev/null \
                        | tail -1 || echo 0)
            local fb_recent_errors
            fb_recent_errors=$(grep "ERROR" /var/log/fail2ban.log 2>/dev/null \
                               | tail -5 | grep -c "$(date '+%Y-%m-%d')" || true); fb_recent_errors=${fb_recent_errors:-0}
            if [[ $fb_recent_errors -gt 0 ]]; then
                _warn "erros hoje:" "$fb_recent_errors erros — veja: tail /var/log/fail2ban.log"
            else
                _ok "erros hoje:" "nenhum"
            fi

        else
            _warn "status:" "instalado mas NÃO está rodando"
        fi
    else
        echo -e "   ${YELLOW}–${NC}  fail2ban não instalado"
    fi

    # ────────────────────────────────────────────────
    # Resultado final
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
        echo -e "   ${GREEN}${BOLD}✔ Tudo OK — nenhum problema encontrado.${NC}"
    elif [[ $issues -eq 0 ]]; then
        echo -e "   ${YELLOW}${BOLD}⚠ $warnings aviso(s) — revise os itens marcados com ⚠${NC}"
    else
        echo -e "   ${RED}${BOLD}✖ $issues problema(s) crítico(s) e $warnings aviso(s) encontrados.${NC}"
        echo -e "   ${RED}Execute 'geoip-fw reload' para tentar corrigir.${NC}"
    fi
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    echo ""

    log "check executado: issues=$issues warnings=$warnings"
    [[ $issues -gt 0 ]] && return 1 || return 0
}

# ── HELP ─────────────────────────────────────────────────
cmd_help() {
    echo ""
    echo -e "${BOLD}geoip-fw — GeoIP Firewall Manager (AMS SOFT)${NC}"
    echo ""
    echo -e "${BOLD}Uso:${NC} geoip-fw <comando> [argumentos]"
    echo ""
    echo -e "${BOLD}Comandos de país:${NC}"
    echo "  status                          Mostra configuração e status atual"
    echo "  add-country BR RU CN            Adiciona países à lista ativa"
    echo "  remove-country RU               Remove país da lista ativa"
    echo "  add-continent south_america     Adiciona todos os países de um preset"
    echo ""
    echo -e "${BOLD}Whitelist:${NC}"
    echo "  whitelist add <IP> [\"label\"]    Adiciona IP/CIDR à whitelist"
    echo "  whitelist remove <IP>           Remove IP/CIDR da whitelist"
    echo "  whitelist list                  Lista todos os IPs na whitelist"
    echo ""
    echo -e "${BOLD}Domínios/APIs (whitelist automática):${NC}"
    echo "  domain list                     Lista domínios e IPs resolvidos"
    echo "  domain sync                     Re-resolve todos os domínios e atualiza whitelist"
    echo "  domain add <dom> [\"label\"]      Adiciona domínio ao resolver automático"
    echo "  domain remove <dom>             Remove domínio e seus IPs da whitelist"
    echo ""
    echo -e "${BOLD}Redes confiáveis por URL (CIDR):${NC}"
    echo "  cidr list                       Lista fontes e quantidade de CIDRs"
    echo "  cidr sync                       Re-baixa CIDRs de todas as fontes"
    echo "  cidr add <url> [\"label\"]        Adiciona fonte de CIDR (URL texto plano)"
    echo "  cidr remove <url>               Remove fonte e seus CIDRs da whitelist"
    echo ""
    echo -e "${BOLD}Operações:${NC}"
    echo "  check                           Auditoria completa do sistema"
  echo "  reload                          Reaplica todas as regras do config.conf"
    echo "  update                          Força atualização das listas GeoIP"
    echo "  test-ip <IP>                    Verifica país e status de bloqueio de um IP"
    echo "  uninstall                       Remove tudo"
    echo ""
    echo -e "${BOLD}Presets de continentes/regiões:${NC}"
    for preset in "${!PRESETS[@]}"; do
        echo "  $(printf '%-22s' "$preset") ${PRESETS[$preset]:0:60}"
    done
    echo ""
    echo -e "${BOLD}Exemplos:${NC}"
    echo "  geoip-fw add-country RU CN"
    echo "  geoip-fw remove-country AR"
    echo "  geoip-fw whitelist add 65.21.100.50 \"Servidor node backup\""
    echo "  geoip-fw whitelist add 95.216.0.0/16 \"Servidorr AS24940\""
    echo "  geoip-fw add-continent europe"
    echo "  geoip-fw test-ip 8.8.8.8"
    echo "  geoip-fw reload"
    echo ""
}

# ── CIDR SYNC ─────────────────────────────────────────────
cmd_cidr_sync() {
    [[ -f "$CIDR_SOURCES_FILE" ]] || { warn "cidr-sources.conf não encontrado: $CIDR_SOURCES_FILE"; return 0; }

    # Em modo blacklist, sincronização de CIDRs é desnecessária
    # (Cloudflare, AWS, Google, etc. já estão em países liberados)
    load_config 2>/dev/null || true
    if [[ "${MODE:-whitelist}" == "blacklist" ]]; then
        info "Modo blacklist ativo — sincronização de CIDRs desnecessária."
        info "Cloudflare, AWS, Google, GitHub, Oracle já estão em países liberados."
        return 0
    fi

    echo -e "\n${CYAN}► Sincronizando fontes CIDR com whitelist...${NC}"

    local added=0 removed=0

    while IFS='|' read -r url desc jq_filter || [[ -n "$url" ]]; do
        [[ "$url" =~ ^#.*$ || -z "$url" ]] && continue
        url=$(echo "$url" | xargs)
        desc=$(echo "$desc" | xargs)
        jq_filter=$(echo "${jq_filter:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        local raw_content
        raw_content=$(curl -s --connect-timeout 10 "$url" 2>/dev/null) || true
        if [[ -z "$raw_content" ]]; then
            warn "Não foi possível baixar: $url"
            continue
        fi

        local new_ips=""
        # Detectar JSON automaticamente (começa com { ou [)
        local first_char="${raw_content:0:1}"
        if [[ "$first_char" == "{" || "$first_char" == "[" ]]; then
            if ! command -v jq &>/dev/null; then
                warn "jq não instalado — instale com: apt-get install jq (pulando $url)"
                continue
            fi
            if [[ -n "$jq_filter" ]]; then
                # Filtro explícito fornecido no terceiro campo
                new_ips=$(echo "$raw_content" | jq -r "$jq_filter" 2>/dev/null \
                    | grep -E '^[0-9a-f:./]+$') || true
            else
                # Extração automática: percorre todos os valores string que parecem CIDRs
                new_ips=$(echo "$raw_content" | jq -r \
                    '.. | strings | select(test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}(/[0-9]+)?$|^[0-9a-f:]+(/[0-9]+)?$"))' \
                    2>/dev/null) || true
            fi
        else
            # Texto puro — uma entrada por linha
            new_ips=$(echo "$raw_content" | grep -E '^[0-9a-f:./]+$') || true
        fi

        if [[ -z "$new_ips" ]]; then
            warn "Nenhum CIDR encontrado em: $url"
            continue
        fi

        local old_count
        old_count=$(grep -cF "|cidr|${url} —" "$WHITELIST_FILE" 2>/dev/null || true)
        sed -i "\#|cidr|${url} —#d" "$WHITELIST_FILE"

        while IFS= read -r cidr; do
            [[ -z "$cidr" ]] && continue
            echo "${cidr}|cidr|${url} — ${desc}" >> "$WHITELIST_FILE"
            added=$((added + 1))
        done <<< "$new_ips"
        removed=$((removed + old_count))

        local ip_count
        ip_count=$(echo "$new_ips" | grep -c .) || ip_count=0
        info "  $desc → $ip_count CIDRs"
    done < "$CIDR_SOURCES_FILE"

    if command -v geoip-shell &>/dev/null; then
        local trusted_ips
        trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session|domain|cidr)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        if [[ -n "$trusted_ips" ]]; then
            geoip-shell configure -z -t "$trusted_ips" &>/dev/null && info "Trusted IPs atualizados no geoip-shell." || true
        fi
    fi

    log "cidr sync: +$added CIDRs inseridos, $removed removidos"
    info "Sincronização CIDR concluída."
}

# ── CIDR ADD ──────────────────────────────────────────────
cmd_cidr_add() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw cidr add <url> [\"descrição\"]"
    local url="$1"
    local desc="${2:-sem descrição}"

    [[ -f "$CIDR_SOURCES_FILE" ]] || touch "$CIDR_SOURCES_FILE"

    if grep -qF "${url}|" "$CIDR_SOURCES_FILE" 2>/dev/null; then
        warn "$url já está em cidr-sources.conf"
        return 0
    fi

    echo "${url}|${desc}" >> "$CIDR_SOURCES_FILE"
    info "Fonte adicionada: $url — $desc"
    echo ""
    echo -e "${YELLOW}Baixando e sincronizando...${NC}"
    cmd_cidr_sync
}

# ── CIDR REMOVE ───────────────────────────────────────────
cmd_cidr_remove() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw cidr remove <url>"
    local url="$1"

    if ! grep -qF "${url}|" "$CIDR_SOURCES_FILE" 2>/dev/null; then
        warn "$url não encontrado em cidr-sources.conf"
        return 0
    fi

    sed -i "\#^${url}|#d" "$CIDR_SOURCES_FILE"
    sed -i "\#|cidr|${url} —#d" "$WHITELIST_FILE"
    info "Fonte removida: $url (e seus CIDRs da whitelist)"

    if command -v geoip-shell &>/dev/null; then
        local trusted_ips
        trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session|domain|cidr)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        if [[ -n "$trusted_ips" ]]; then
            geoip-shell configure -z -t "$trusted_ips" &>/dev/null || true
        else
            geoip-shell configure -z -t none &>/dev/null || true
        fi
    fi

    log "cidr remove: $url"
}

# ── CIDR LIST ─────────────────────────────────────────────
cmd_cidr_list() {
    echo ""
    echo -e "${BOLD}═══ Fontes CIDR Configuradas ═══${NC}"

    if [[ ! -f "$CIDR_SOURCES_FILE" ]]; then
        warn "cidr-sources.conf não encontrado: $CIDR_SOURCES_FILE"
        return 0
    fi

    local count=0
    while IFS='|' read -r url desc jq_filter || [[ -n "$url" ]]; do
        [[ "$url" =~ ^#.*$ || -z "$url" ]] && continue
        url=$(echo "$url" | xargs)
        desc=$(echo "$desc" | xargs)
        local ip_count
        ip_count=$(grep -cF "|cidr|${url} —" "$WHITELIST_FILE" 2>/dev/null || true)
        echo -e "  \033[0;34m$(printf '%-52s' "$url")${NC} $desc  ${YELLOW}[${ip_count} CIDRs]${NC}"
        count=$((count + 1))
    done < "$CIDR_SOURCES_FILE"

    echo -e "\n  Total: $count fontes"
    echo ""
}

# ── MENU CIDR (wrapper) ───────────────────────────────────
menu_cidr_wrapper() {
    while true; do
        clear
        echo -e "\033[0;34m${BOLD}  ╔══════════════════════════════════════╗${NC}"
        echo -e "\033[0;34m${BOLD}  ║  Redes Confiáveis — CIDR por URL     ║${NC}"
        echo -e "\033[0;34m${BOLD}  ╚══════════════════════════════════════╝${NC}"
        echo ""
        cmd_cidr_list
        echo "  1) Sincronizar agora (re-baixar todas)"
        echo "  2) Adicionar fonte"
        echo "  3) Remover fonte"
        echo "  0) Voltar"
        echo ""
        ask "Escolha: "
        read -r sub
        case "$sub" in
            1) echo ""; cmd_cidr_sync ;;
            2)
                echo ""
                ask "URL da lista de IPs (texto plano, 1 CIDR por linha): "
                read -r new_url
                [[ -z "$new_url" ]] && continue
                ask "Descrição: "
                read -r new_desc
                cmd_cidr_add "$new_url" "$new_desc"
                ;;
            3)
                echo ""
                ask "URL a remover: "
                read -r rm_url
                [[ -z "$rm_url" ]] && continue
                cmd_cidr_remove "$rm_url"
                ;;
            0) return ;;
            *) warn "Opção inválida." ;;
        esac
        echo ""
        ask "Pressione ENTER para continuar..."
        read -r
    done
}

# ── DOMAIN RESOLVE ────────────────────────────────────────
resolve_domain() {
    local domain="$1"
    local v4 v6
    v4=$(dig +short A    "$domain" 2>/dev/null | grep -E '^[0-9]+\.' | tr '\n' ' ') || true
    v6=$(dig +short AAAA "$domain" 2>/dev/null | grep -E '^[0-9a-f:]+$' | tr '\n' ' ') || true
    echo "${v4}${v6}" | xargs
}

# ── DOMAIN SYNC ───────────────────────────────────────────
cmd_domain_sync() {
    [[ -f "$DOMAINS_FILE" ]] || { warn "domains.conf não encontrado: $DOMAINS_FILE"; return 0; }

    # Em modo blacklist, sincronização de domínios é desnecessária
    # (países já liberados incluem todos os serviços)
    load_config 2>/dev/null || true
    if [[ "${MODE:-whitelist}" == "blacklist" ]]; then
        info "Modo blacklist ativo — sincronização de domínios desnecessária."
        info "Os países já liberados incluem todos os serviços configurados."
        return 0
    fi

    echo -e "\n${CYAN}► Sincronizando domínios com whitelist...${NC}"

    local added=0 removed=0

    while IFS='|' read -r domain desc || [[ -n "$domain" ]]; do
        [[ "$domain" =~ ^#.*$ || -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs)
        desc=$(echo "$desc" | xargs)

        local new_ips
        new_ips=$(resolve_domain "$domain")
        if [[ -z "$new_ips" ]]; then
            warn "Não foi possível resolver: $domain"
            continue
        fi

        local old_count
        old_count=$(grep -c "|domain|${domain} —" "$WHITELIST_FILE" 2>/dev/null || true)
        sed -i "/|domain|${domain} —/d" "$WHITELIST_FILE"

        for ip in $new_ips; do
            echo "${ip}|domain|${domain} — ${desc}" >> "$WHITELIST_FILE"
            added=$((added + 1))
        done
        removed=$((removed + old_count))

        info "  $domain → $new_ips"
    done < "$DOMAINS_FILE"

    if command -v geoip-shell &>/dev/null; then
        local trusted_ips
        trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session|domain|cidr)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        if [[ -n "$trusted_ips" ]]; then
            geoip-shell configure -z -t "$trusted_ips" &>/dev/null && info "Trusted IPs atualizados no geoip-shell." || true
        fi
    fi

    log "domain sync: +$added IPs inseridos, $removed removidos"
    info "Sincronização concluída."
}

# ── DOMAIN ADD ────────────────────────────────────────────
cmd_domain_add() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw domain add <domínio> [\"descrição\"]"
    local domain="$1"
    local desc="${2:-sem descrição}"

    [[ -f "$DOMAINS_FILE" ]] || touch "$DOMAINS_FILE"

    if grep -q "^${domain}|" "$DOMAINS_FILE" 2>/dev/null; then
        warn "$domain já está em domains.conf"
        return 0
    fi

    echo "${domain}|${desc}" >> "$DOMAINS_FILE"
    info "Domínio adicionado: $domain — $desc"
    echo ""
    echo -e "${YELLOW}Resolvendo e sincronizando...${NC}"
    cmd_domain_sync
}

# ── DOMAIN REMOVE ─────────────────────────────────────────
cmd_domain_remove() {
    [[ $# -eq 0 ]] && die "Uso: geoip-fw domain remove <domínio>"
    local domain="$1"

    if ! grep -q "^${domain}|" "$DOMAINS_FILE" 2>/dev/null; then
        warn "$domain não encontrado em domains.conf"
        return 0
    fi

    sed -i "/^${domain}|/d" "$DOMAINS_FILE"
    sed -i "/|domain|${domain} —/d" "$WHITELIST_FILE"
    info "Domínio removido: $domain (e seus IPs da whitelist)"

    if command -v geoip-shell &>/dev/null; then
        local trusted_ips
        trusted_ips=$(grep -vE "^#|^$" "$WHITELIST_FILE" | grep -E "\|(manual|session|domain|cidr)\|" | cut -d'|' -f1 | tr '\n' ' ' | xargs) || true
        if [[ -n "$trusted_ips" ]]; then
            geoip-shell configure -z -t "$trusted_ips" &>/dev/null || true
        else
            geoip-shell configure -z -t none &>/dev/null || true
        fi
    fi

    log "domain remove: $domain"
}

# ── DOMAIN LIST ───────────────────────────────────────────
cmd_domain_list() {
    echo ""
    echo -e "${BOLD}═══ Domínios Configurados ═══${NC}"

    if [[ ! -f "$DOMAINS_FILE" ]]; then
        warn "domains.conf não encontrado: $DOMAINS_FILE"
        return 0
    fi

    local count=0
    while IFS='|' read -r domain desc || [[ -n "$domain" ]]; do
        [[ "$domain" =~ ^#.*$ || -z "$domain" ]] && continue
        domain=$(echo "$domain" | xargs)
        desc=$(echo "$desc" | xargs)
        local ip_count
        ip_count=$(grep -c "|domain|${domain} —" "$WHITELIST_FILE" 2>/dev/null || true)
        echo -e "  ${CYAN}$(printf '%-40s' "$domain")${NC} $desc  ${YELLOW}[${ip_count} IPs]${NC}"
        count=$((count + 1))
    done < "$DOMAINS_FILE"

    echo -e "\n  Total: $count domínios"
    echo ""
}

# ── MENU DOMAIN ───────────────────────────────────────────
menu_domains() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════╗${NC}"
        echo -e "${CYAN}${BOLD}  ║  Domínios/APIs — Whitelist Auto  ║${NC}"
        echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════╝${NC}"
        echo ""
        cmd_domain_list
        echo "  1) Sincronizar agora (re-resolver todos)"
        echo "  2) Adicionar domínio"
        echo "  3) Remover domínio"
        echo "  0) Voltar"
        echo ""
        ask "Escolha: "
        read -r sub
        case "$sub" in
            1) echo ""; cmd_domain_sync ;;
            2)
                echo ""
                ask "Domínio (ex: api.exemplo.com): "
                read -r new_dom
                [[ -z "$new_dom" ]] && continue
                ask "Descrição: "
                read -r new_desc
                cmd_domain_add "$new_dom" "$new_desc"
                ;;
            3)
                echo ""
                ask "Domínio a remover: "
                read -r rm_dom
                [[ -z "$rm_dom" ]] && continue
                cmd_domain_remove "$rm_dom"
                ;;
            0) return ;;
            *) warn "Opção inválida." ;;
        esac
        echo ""
        ask "Pressione ENTER para continuar..."
        read -r
    done
}

# ═══════════════════════════════════════════════════════════
# ROTEADOR DE COMANDOS
# ═══════════════════════════════════════════════════════════

[[ $EUID -ne 0 ]] && die "Execute como root: sudo geoip-fw $*"
[[ $# -eq 0 ]] && { cmd_help; exit 0; }

CMD="$1"; shift || true

case "$CMD" in
    status)           cmd_status ;;
    add-country)      cmd_add_country "$@" ;;
    remove-country)   cmd_remove_country "$@" ;;
    add-continent)    cmd_add_continent "$@" ;;
    whitelist)
        SUB="${1:-}"; shift || true
        case "$SUB" in
            add)    cmd_whitelist_add "$@" ;;
            remove) cmd_whitelist_remove "$@" ;;
            list)   cmd_whitelist_list ;;
            *)      die "Subcomando inválido: $SUB. Use: add, remove, list" ;;
        esac
        ;;
    domain)
        SUB="${1:-}"; shift || true
        case "$SUB" in
            sync)   cmd_domain_sync ;;
            add)    cmd_domain_add "$@" ;;
            remove) cmd_domain_remove "$@" ;;
            list)   cmd_domain_list ;;
            *)      die "Subcomando inválido: $SUB. Use: sync, add, remove, list" ;;
        esac
        ;;
    cidr)
        SUB="${1:-}"; shift || true
        case "$SUB" in
            sync)   cmd_cidr_sync ;;
            add)    cmd_cidr_add "$@" ;;
            remove) cmd_cidr_remove "$@" ;;
            list)   cmd_cidr_list ;;
            *)      die "Subcomando inválido: $SUB. Use: sync, add, remove, list" ;;
        esac
        ;;
    check)    cmd_check ;;
    reload)   cmd_reload ;;
    pause)    cmd_pause ;;
    enable)   cmd_enable ;;
    disable)  cmd_disable ;;
    update)   cmd_update ;;
    test-ip)  cmd_test_ip "$@" ;;
    uninstall) cmd_uninstall ;;
    help|--help|-h) cmd_help ;;
    *) error "Comando desconhecido: $CMD"; cmd_help; exit 1 ;;
esac
WRAPPER_EOF

    chmod +x "$WRAPPER_BIN"
    info "Wrapper instalado em $WRAPPER_BIN"
}

# ═══════════════════════════════════════════════════════════
# CONFIGURAR CRON
# ═══════════════════════════════════════════════════════════

setup_cron() {
    step "Configurando atualização automática"

    local cron_file="/etc/cron.d/geoip-firewall"
    load_config 2>/dev/null || true

    cat > "$cron_file" << EOF
# GeoIP Firewall — atualização automática (AMS SOFT)
# Toda segunda-feira às 04:15
15 4 * * 1 root /usr/local/bin/geoip-fw update >> /var/log/geoip-firewall.log 2>&1
EOF

    # Em modo whitelist, adicionar sync de domínios e CIDRs (necessário para liberar serviços em países bloqueados)
    # Em modo blacklist, NÃO adicionar (países já liberados incluem todos os serviços)
    if [[ "${MODE:-whitelist}" == "whitelist" ]]; then
        cat >> "$cron_file" << EOF
# Resolução DNS de domínios (APIs/gateways) — a cada 6 horas
0 */6 * * * root /usr/local/bin/geoip-fw domain sync >> /var/log/geoip-firewall.log 2>&1
# Download de CIDRs confiáveis (Cloudflare, etc.) — diariamente às 02:00
0 2 * * * root /usr/local/bin/geoip-fw cidr sync >> /var/log/geoip-firewall.log 2>&1
EOF
        info "Cron configurado: atualização toda segunda às 04:15 + sync de domínios a cada 6h"
    else
        info "Cron configurado: atualização toda segunda às 04:15 (sem sync de domínios/CIDRs em modo blacklist)"
    fi
}

# ═══════════════════════════════════════════════════════════
# APLICAR CONFIGURAÇÃO INICIAL
# ═══════════════════════════════════════════════════════════

apply_initial_config() {
    step "Aplicando configuração GeoIP"

    if [[ ! -f "$GEOIP_SHELL_DIR/geoip-shell-install.sh" ]]; then
        warn "Instalador do geoip-shell não encontrado em $GEOIP_SHELL_DIR"
        warn "Execute 'geoip-fw reload' após verificar a instalação."
        return 0
    fi

    # Rodar geoip-shell-install.sh apenas se o binário ainda não está no PATH
    # (re-instalações não devem apagar a configuração existente)
    if ! command -v geoip-shell &>/dev/null; then
        local gs_fw_flag="nft"
        [[ "${FW_BACKEND:-nftables}" == "iptables" ]] && gs_fw_flag="ipt"

        echo -e "   Instalando geoip-shell (backend: $gs_fw_flag)..."
        bash "$GEOIP_SHELL_DIR/geoip-shell-install.sh" \
            -w "$gs_fw_flag" \
            -z \
            2>&1 | grep -Ei "(install|error|warning)" || true
    else
        info "geoip-shell já instalado — atualizando configuração."
    fi

    # Configurar modo, países e interface via geoip-shell configure
    if command -v geoip-shell &>/dev/null; then
        echo -e "   Configurando geoip-shell (modo: $GEOIP_MODE, países: $(format_countries "$COUNTRIES"))..."

        # Usar array para garantir que -l receba os ranges como argumento único
        local -a gs_cmd_args=(-z -m "$GEOIP_MODE" -c "$COUNTRIES" -i "$NETWORK_IF" -u "ripe" -f "ipv4 ipv6" -s "disable")

        # Em whitelist usa -l (LAN), em blacklist usa -t (trusted) para redes privadas
        local private_ranges="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/8 fd00::/8 fe80::/10"
        if [[ "$GEOIP_MODE" == "blacklist" && "${GEOIP_ALLOW_PRIVATE:-yes}" == "yes" ]]; then
            gs_cmd_args+=(-t "$private_ranges")
        elif [[ "$GEOIP_MODE" == "whitelist" && "${GEOIP_ALLOW_PRIVATE:-yes}" == "yes" ]]; then
            gs_cmd_args+=(-l "$private_ranges")
        fi

        geoip-shell configure "${gs_cmd_args[@]}" \
            2>&1 | grep -Ei "(install|error|warning|bloqu|allow)" || true
    else
        warn "geoip-shell não encontrado. Execute 'geoip-fw reload' manualmente."
    fi

    info "Configuração GeoIP aplicada."
}

# ═══════════════════════════════════════════════════════════
# RELATÓRIO FINAL
# ═══════════════════════════════════════════════════════════

final_report() {
    echo ""
    echo -e "${GREEN}${BOLD}============================================${NC}"
    echo -e "${GREEN}${BOLD}   ✔ Instalação concluída com sucesso!      ${NC}"
    echo -e "${GREEN}${BOLD}============================================${NC}"
    echo ""
    echo -e "  ${BOLD}Modo:${NC}        $GEOIP_MODE"
    echo -e "  ${BOLD}Países:${NC}      $(format_countries "$COUNTRIES")"
    echo -e "  ${BOLD}Interface:${NC}   $NETWORK_IF"
    echo -e "  ${BOLD}Config:${NC}      $CONF_FILE"
    echo -e "  ${BOLD}Whitelist:${NC}   $WHITELIST_FILE"
    echo -e "  ${BOLD}Log:${NC}         $LOG_FILE"
    echo ""
    echo -e "${CYAN}${BOLD}  Comandos úteis:${NC}"
    echo "  geoip-fw status"
    echo "  geoip-fw add-country RU CN"
    echo "  geoip-fw remove-country AR"
    echo "  geoip-fw add-continent europe"
    echo "  geoip-fw whitelist add 65.21.100.50 \"Servidorr backup\""
    echo "  geoip-fw whitelist list"
    echo "  geoip-fw test-ip 8.8.8.8"
    echo "  geoip-fw reload"
    echo ""
    echo -e "${YELLOW}  Atualização automática:${NC} toda segunda às 04:15"
    echo -e "${YELLOW}  Para editar manualmente:${NC} nano $CONF_FILE"
    echo -e "${YELLOW}  Para remover tudo:${NC}       geoip-fw uninstall"
    echo ""
}

# ═══════════════════════════════════════════════════════════
# MENU INTERATIVO — MODO PÓS-INSTALAÇÃO
# ═══════════════════════════════════════════════════════════

# Banco de países em português → código ISO (para busca por nome)
declare -A COUNTRY_CODES=(
    ["brasil"]="BR"               ["argentina"]="AR"            ["uruguai"]="UY"
    ["paraguai"]="PY"             ["bolivia"]="BO"              ["chile"]="CL"
    ["colombia"]="CO"             ["peru"]="PE"                 ["equador"]="EC"
    ["venezuela"]="VE"            ["guiana"]="GY"               ["suriname"]="SR"
    ["mexico"]="MX"               ["cuba"]="CU"                 ["estados unidos"]="US"
    ["canada"]="CA"               ["portugal"]="PT"             ["espanha"]="ES"
    ["franca"]="FR"               ["alemanha"]="DE"             ["italia"]="IT"
    ["reino unido"]="GB"          ["russia"]="RU"               ["china"]="CN"
    ["japao"]="JP"                ["coreia do sul"]="KR"        ["india"]="IN"
    ["australia"]="AU"            ["africa do sul"]="ZA"        ["angola"]="AO"
    ["mocambique"]="MZ"           ["cabo verde"]="CV"           ["nigeria"]="NG"
    ["turquia"]="TR"              ["israel"]="IL"               ["arabia saudita"]="SA"
    ["emirados arabes"]="AE"      ["paises baixos"]="NL"        ["belgica"]="BE"
    ["suica"]="CH"                ["austria"]="AT"              ["polonia"]="PL"
    ["suecia"]="SE"               ["noruega"]="NO"              ["dinamarca"]="DK"
    ["finlandia"]="FI"            ["ucrania"]="UA"              ["romenia"]="RO"
    ["hungria"]="HU"              ["republica checa"]="CZ"      ["grecia"]="GR"
    ["bulgaria"]="BG"             ["irlanda"]="IE"              ["nova zelandia"]="NZ"
    ["singapura"]="SG"            ["indonesia"]="ID"            ["tailandia"]="TH"
    ["vietna"]="VN"               ["paquistao"]="PK"            ["bangladesh"]="BD"
    ["egito"]="EG"                ["kenya"]="KE"                ["panama"]="PA"
    ["costa rica"]="CR"           ["republica dominicana"]="DO" ["haiti"]="HT"
    ["guatemala"]="GT"            ["honduras"]="HN"             ["marrocos"]="MA"
    ["argelia"]="DZ"              ["tunisia"]="TN"              ["ghana"]="GH"
    ["senegal"]="SN"              ["etiopia"]="ET"              ["tanzania"]="TZ"
    ["camboja"]="KH"              ["myanmar"]="MM"              ["sri lanka"]="LK"
    ["nepal"]="NP"                ["filipinas"]="PH"            ["malasia"]="MY"
)

# ── Verifica estado da instalação ──────────────────────────
check_installation_state() {
    local conf=false wrapper=false geoip=false
    [[ -f "$CONF_FILE" ]]       && conf=true
    [[ -x "$WRAPPER_BIN" ]]     && wrapper=true
    [[ -d "$GEOIP_SHELL_DIR" ]] && geoip=true

    if $conf && $wrapper && $geoip; then
        echo "complete"
    elif ! $conf && ! $wrapper && ! $geoip; then
        echo "fresh"
    else
        echo "partial"
    fi
}

# ── Exibe resumo do estado atual ───────────────────────────
show_current_summary() {
    local mode="" countries="" wl_count=0

    if [[ -f "$CONF_FILE" ]]; then
        mode=$(grep -E '^MODE=' "$CONF_FILE" | cut -d'"' -f2)
        countries=$(grep -E '^COUNTRIES=' "$CONF_FILE" | cut -d'"' -f2)
    fi

    if [[ -f "$WHITELIST_FILE" ]]; then
        wl_count=$(grep -cE '\|(auto|manual|session|domain)\|' "$WHITELIST_FILE" 2>/dev/null || echo 0)
    fi

    # Detectar estado real do firewall
    # NOTA: não usar grep -q com pipe — causa SIGPIPE no iptables com set -euo pipefail
    if iptables -t mangle -L GEOIP-SHELL_IN -n 2>/dev/null | grep "DROP\|ACCEPT" >/dev/null 2>&1; then
        echo -e "  ${GREEN}${BOLD}● GeoIP Firewall ATIVO${NC}"
    elif crontab -l 2>/dev/null | grep -q "geoip-shell-persistence"; then
        echo -e "  ${YELLOW}${BOLD}⚠ GeoIP Firewall PAUSADO — regras voltam no reboot${NC}"
    else
        echo -e "  ${RED}${BOLD}✖ GeoIP Firewall DESATIVADO — todo tráfego liberado${NC}"
    fi
    echo -e "  Modo: ${CYAN}${BOLD}${mode}${NC}  │  Países: ${CYAN}$(format_countries "$countries")${NC}  │  IPs na whitelist: ${CYAN}${wl_count}${NC}"
    echo ""
}

# ── Busca país por nome (substring) ───────────────────────
search_country() {
    local query="${1,,}"
    local -a matches=()
    local -a codes=()

    for name in "${!COUNTRY_CODES[@]}"; do
        if [[ "$name" == *"$query"* ]]; then
            matches+=("$name")
            codes+=("${COUNTRY_CODES[$name]}")
        fi
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        warn "Nenhum país encontrado para: $query"
        SELECTED_COUNTRY_CODE=""
        SELECTED_COUNTRY_NAME=""
        return 1
    fi

    if [[ ${#matches[@]} -eq 1 ]]; then
        SELECTED_COUNTRY_CODE="${codes[0]}"
        SELECTED_COUNTRY_NAME="${matches[0]}"
        return 0
    fi

    echo ""
    echo -e "${BOLD}Resultados para \"$query\":${NC}"
    for i in "${!matches[@]}"; do
        # Capitaliza primeira letra de cada palavra
        local display_name
        display_name=$(echo "${matches[$i]}" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}')
        echo "  $((i+1))) $display_name (${codes[$i]})"
    done
    echo "  0) Voltar"
    echo ""
    ask "Escolha: "
    read -r sel
    if [[ "$sel" == "0" || -z "$sel" ]]; then
        SELECTED_COUNTRY_CODE=""
        SELECTED_COUNTRY_NAME=""
        return 1
    fi
    if [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le ${#matches[@]} ]]; then
        local idx=$((sel-1))
        SELECTED_COUNTRY_CODE="${codes[$idx]}"
        SELECTED_COUNTRY_NAME="${matches[$idx]}"
        return 0
    fi
    warn "Opção inválida."
    SELECTED_COUNTRY_CODE=""
    SELECTED_COUNTRY_NAME=""
    return 1
}

# ── Opção 1: Liberar IP (whitelist) ───────────────────────
menu_whitelist_ip() {
    echo ""
    echo -e "${BOLD}═══ Liberar IP / Faixa ═══${NC}"
    echo ""
    echo -e "  Exemplos: ${CYAN}192.168.1.50${NC}  ou  ${CYAN}65.21.0.0/16${NC}"
    echo ""
    ask "IP ou faixa CIDR: "
    read -r ip_input
    ip_input="${ip_input// /}"

    if [[ -z "$ip_input" ]]; then
        warn "Nenhum IP informado."
        return
    fi

    ask "Descrição (opcional — para lembrar depois): "
    read -r ip_desc
    ip_desc="${ip_desc:-sem descrição}"

    echo ""
    geoip-fw whitelist add "$ip_input" "$ip_desc" || true
    echo ""
}

# ── Opção 2: Bloquear IP manualmente ──────────────────────
menu_blacklist_ip() {
    local BLACKLIST_MANUAL="$CONF_DIR/blacklist-manual.conf"
    echo ""
    echo -e "${BOLD}═══ Bloquear IP / Faixa Permanentemente ═══${NC}"
    echo ""
    echo -e "  Exemplos: ${CYAN}45.33.32.156${NC}  ou  ${CYAN}45.33.0.0/16${NC}"
    echo ""
    ask "IP ou faixa CIDR: "
    read -r ip_input
    ip_input="${ip_input// /}"

    if [[ -z "$ip_input" ]]; then
        warn "Nenhum IP informado."
        return
    fi

    if ! echo "$ip_input" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$'; then
        warn "Formato inválido: $ip_input. Use IP (ex: 1.2.3.4) ou CIDR (ex: 1.2.3.0/24)"
        return
    fi

    if [[ -f "$BLACKLIST_MANUAL" ]] && grep -q "^${ip_input}|" "$BLACKLIST_MANUAL" 2>/dev/null; then
        warn "$ip_input já está na blacklist manual."
        return
    fi

    ask "Motivo (opcional): "
    read -r ip_desc
    ip_desc="${ip_desc:-sem descrição}"

    # Detectar família: IPv6 contém ':', IPv4 não
    local ip_family="ipv4"
    [[ "$ip_input" == *:* ]] && ip_family="ipv6"

    # Aplicar via nftables ou iptables/ip6tables
    local applied=false
    if command -v nft &>/dev/null; then
        local set_name="geoip-manual-block-${ip_family}"
        local nft_type="ipv4_addr"; [[ "$ip_family" == "ipv6" ]] && nft_type="ipv6_addr"
        local nft_match="ip saddr"; [[ "$ip_family" == "ipv6" ]] && nft_match="ip6 saddr"
        if ! nft list sets inet 2>/dev/null | grep -q "$set_name"; then
            nft add set inet filter "$set_name" \
                "{ type ${nft_type}; flags interval; }" 2>/dev/null || true
            nft add rule inet filter input \
                "$nft_match" "@${set_name}" drop 2>/dev/null || true
        fi
        nft add element inet filter "$set_name" "{ $ip_input }" 2>/dev/null \
            && applied=true || true
    fi
    if ! $applied; then
        if [[ "$ip_family" == "ipv6" ]] && command -v ip6tables &>/dev/null; then
            ip6tables -I INPUT -s "$ip_input" -j DROP 2>/dev/null && applied=true || true
        elif command -v iptables &>/dev/null; then
            iptables -I INPUT -s "$ip_input" -j DROP 2>/dev/null && applied=true || true
        fi
    fi

    # Persistir
    touch "$BLACKLIST_MANUAL"
    echo "${ip_input}|manual|${ip_desc}" >> "$BLACKLIST_MANUAL"

    echo ""
    if $applied; then
        info "IP $ip_input bloqueado permanentemente — regra ativa."
    else
        warn "IP salvo na blacklist mas não foi possível aplicar a regra agora."
        warn "Verifique se o firewall está ativo e tente novamente."
    fi
    log "Blacklist manual add: $ip_input — $ip_desc"
}

# ── Opções 3 e 4: Gerenciar países ────────────────────────
menu_manage_countries() {
    local action="$1"  # "allow" ou "block"
    local mode="" label_add="" label_remove=""

    if [[ -f "$CONF_FILE" ]]; then
        mode=$(grep -E '^MODE=' "$CONF_FILE" | cut -d'"' -f2)
    fi

    if [[ "$action" == "allow" ]]; then
        label_add="Adicionar país PERMITIDO"
        label_remove="Remover país da lista"
    else
        label_add="Adicionar país BLOQUEADO"
        label_remove="Remover país do bloqueio"
    fi

    while true; do
        echo ""
        echo -e "${BOLD}═══ Gerenciar Países ═══${NC}"
        echo -e "  Modo atual: ${CYAN}${mode}${NC}"
        echo ""
        echo "  1) $label_add (buscar por nome)"
        echo "  2) $label_add (usar grupo / continente)"
        echo "  3) $label_remove"
        echo "  0) Voltar"
        echo ""
        ask "Escolha: "
        read -r sub
        case "$sub" in
            1)
                echo ""
                ask "Nome ou parte do nome do país (ex: \"alem\"): "
                read -r query
                if search_country "$query"; then
                    local display_name
                    display_name=$(echo "$SELECTED_COUNTRY_NAME" | \
                        awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}')
                    echo ""
                    echo -e "  País: ${CYAN}${BOLD}$display_name (${SELECTED_COUNTRY_CODE})${NC}"
                    ask "Confirmar? [S/n]: "
                    read -r confirm
                    if [[ "${confirm,,}" != "n" ]]; then
                        echo ""
                        geoip-fw add-country "$SELECTED_COUNTRY_CODE" || true
                        echo ""
                        info "Aplicando alterações..."
                        geoip-fw reload || true
                    fi
                fi
                ;;
            2)
                echo ""
                echo -e "${BOLD}Grupos disponíveis:${NC}"
                echo "  1) América do Sul completa"
                echo "  2) MERCOSUL"
                echo "  3) América Latina"
                echo "  4) Europa"
                echo "  5) América do Norte"
                echo "  6) Mundo Lusófono"
                echo "  0) Voltar"
                echo ""
                ask "Escolha: "
                read -r grp
                local preset_key=""
                case "$grp" in
                    1) preset_key="south_america" ;;
                    2) preset_key="mercosul" ;;
                    3) preset_key="latin_america" ;;
                    4) preset_key="europe" ;;
                    5) preset_key="north_america" ;;
                    6) preset_key="portuguese_world" ;;
                    0) ;;
                    *) warn "Opção inválida." ;;
                esac
                if [[ -n "$preset_key" ]]; then
                    echo ""
                    geoip-fw add-continent "$preset_key" || true
                    echo ""
                    info "Aplicando alterações..."
                    geoip-fw reload || true
                fi
                ;;
            3)
                echo ""
                ask "Código ISO do país a remover (ex: DE, RU): "
                read -r code
                code="${code^^}"
                if [[ -z "$code" ]]; then
                    warn "Código não informado."
                else
                    echo ""
                    geoip-fw remove-country "$code" || true
                    echo ""
                    info "Aplicando alterações..."
                    geoip-fw reload || true
                fi
                ;;
            0) return ;;
            *) warn "Opção inválida." ;;
        esac
        echo ""
        ask "Gerenciar mais países? [s/N]: "
        read -r more
        [[ "${more,,}" != "s" ]] && return
    done
}

# ── Opção 5: Ver listas ────────────────────────────────────
menu_view_lists() {
    local BLACKLIST_MANUAL="$CONF_DIR/blacklist-manual.conf"
    echo ""
    echo -e "${BOLD}═══ IPs Liberados (whitelist) ═══${NC}"
    if [[ -f "$WHITELIST_FILE" ]]; then
        while IFS='|' read -r ip type desc; do
            [[ "$ip" =~ ^#.*$ || -z "$ip" ]] && continue
            printf "  ${CYAN}[%-7s]${NC}  %-22s %s\n" "$type" "$ip" "$desc"
        done < "$WHITELIST_FILE"
    else
        echo "  (arquivo não encontrado)"
    fi

    echo ""
    echo -e "${BOLD}═══ IPs Bloqueados Manualmente ═══${NC}"
    if [[ -f "$BLACKLIST_MANUAL" ]] && grep -qvE '^#|^$' "$BLACKLIST_MANUAL" 2>/dev/null; then
        while IFS='|' read -r ip type desc; do
            [[ "$ip" =~ ^#.*$ || -z "$ip" ]] && continue
            printf "  ${RED}[%-7s]${NC}  %-22s %s\n" "$type" "$ip" "$desc"
        done < "$BLACKLIST_MANUAL"
    else
        echo "  (nenhum IP bloqueado manualmente)"
    fi

    echo ""
    echo -e "${BOLD}═══ Países configurados ═══${NC}"
    local countries="" mode=""
    if [[ -f "$CONF_FILE" ]]; then
        countries=$(grep -E '^COUNTRIES=' "$CONF_FILE" | cut -d'"' -f2)
        mode=$(grep -E '^MODE=' "$CONF_FILE" | cut -d'"' -f2)
    fi
    echo -e "  Modo: ${CYAN}${mode}${NC}"
    for code in $countries; do
        echo "  • $code — $(country_name "$code")"
    done

    echo ""
    ask "Deseja remover algum IP da whitelist? [s/N]: "
    read -r rm_choice
    if [[ "${rm_choice,,}" == "s" ]]; then
        ask "IP a remover: "
        read -r rm_ip
        [[ -n "$rm_ip" ]] && { echo ""; geoip-fw whitelist remove "$rm_ip" || true; }
    fi
    echo ""
}

# ── Opção 6: Domínios/APIs ────────────────────────────────
menu_domains() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}${BOLD}  ║   Domínios/APIs — Whitelist Auto     ║${NC}"
        echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════╝${NC}"
        echo ""
        geoip-fw domain list || true
        echo "  1) Sincronizar agora (re-resolver todos)"
        echo "  2) Adicionar domínio"
        echo "  3) Remover domínio"
        echo "  0) Voltar"
        echo ""
        ask "Escolha: "
        read -r sub
        case "$sub" in
            1)
                echo ""
                geoip-fw domain sync || true
                ;;
            2)
                echo ""
                ask "Domínio (ex: api.exemplo.com): "
                read -r new_dom
                [[ -z "$new_dom" ]] && continue
                ask "Descrição: "
                read -r new_desc
                echo ""
                geoip-fw domain add "$new_dom" "$new_desc" || true
                ;;
            3)
                echo ""
                ask "Domínio a remover: "
                read -r rm_dom
                [[ -z "$rm_dom" ]] && continue
                echo ""
                geoip-fw domain remove "$rm_dom" || true
                ;;
            0) return ;;
            *) warn "Opção inválida." ;;
        esac
        echo ""
        ask "Pressione ENTER para continuar..."
        read -r
    done
}

# ── Opção 7: Redes confiáveis (CIDR) ─────────────────────
menu_cidr() {
    while true; do
        clear
        echo -e "\033[0;34m${BOLD}  ╔══════════════════════════════════════╗${NC}"
        echo -e "\033[0;34m${BOLD}  ║  Redes Confiáveis — CIDR por URL     ║${NC}"
        echo -e "\033[0;34m${BOLD}  ╚══════════════════════════════════════╝${NC}"
        echo ""
        geoip-fw cidr list || true
        echo "  1) Sincronizar agora (re-baixar todas)"
        echo "  2) Adicionar fonte"
        echo "  3) Remover fonte"
        echo "  0) Voltar"
        echo ""
        ask "Escolha: "
        read -r sub
        case "$sub" in
            1) echo ""; geoip-fw cidr sync || true ;;
            2)
                echo ""
                ask "URL da lista (texto plano, 1 CIDR por linha): "
                read -r new_url
                [[ -z "$new_url" ]] && continue
                ask "Descrição: "
                read -r new_desc
                echo ""
                geoip-fw cidr add "$new_url" "$new_desc" || true
                ;;
            3)
                echo ""
                ask "URL a remover: "
                read -r rm_url
                [[ -z "$rm_url" ]] && continue
                echo ""
                geoip-fw cidr remove "$rm_url" || true
                ;;
            0) return ;;
            *) warn "Opção inválida." ;;
        esac
        echo ""
        ask "Pressione ENTER para continuar..."
        read -r
    done
}

# ── Opção 10: Alterar modo de operação ─────────────────────
menu_change_mode() {
    load_config 2>/dev/null || true

    local current_mode="${MODE:-whitelist}"
    local new_mode
    local apply_preset=""

    echo ""
    echo -e "${BOLD}═══ Alterar Modo de Operação ═══${NC}"
    echo ""
    echo -e "  Modo atual: ${CYAN}${BOLD}${current_mode}${NC}"
    echo ""

    if [[ "$current_mode" == "whitelist" ]]; then
        echo -e "  ${BOLD}Whitelist${NC} = permite APENAS os países listados"
        echo -e "  ${BOLD}Blacklist${NC} = bloqueia APENAS os países listados"
        echo ""
        echo "  Deseja alterar para blacklist?"
        echo "  (Recomendado: use o preset 'amssoft_blacklist' para bloquear bots)"
        echo ""
        echo "  1) Alterar para blacklist"
        echo "  2) Alterar para blacklist + aplicar preset amssoft_blacklist"
        echo "  0) Voltar"
        echo ""
        ask "Escolha: "
        read -r sub
        case "$sub" in
            1)
                new_mode="blacklist"
                ;;
            2)
                new_mode="blacklist"
                apply_preset="amssoft_blacklist"
                ;;
            *)
                return
                ;;
        esac
    else
        echo -e "  ${BOLD}Blacklist${NC} = bloqueia APENAS os países listados"
        echo -e "  ${BOLD}Whitelist${NC} = permite APENAS os países listados"
        echo ""
        echo "  Deseja alterar para whitelist?"
        echo ""
        echo "  1) Alterar para whitelist"
        echo "  2) Alterar para whitelist + aplicar preset latin_america"
        echo "  0) Voltar"
        echo ""
        ask "Escolha: "
        read -r sub
        case "$sub" in
            1)
                new_mode="whitelist"
                ;;
            2)
                new_mode="whitelist"
                apply_preset="latin_america"
                ;;
            *)
                return
                ;;
        esac
    fi

    # ── 1. Atualizar config.conf ───────────────────────────
    step "Atualizando configuração..."

    # Atualizar modo
    sed -i "s|^MODE=.*|MODE=\"$new_mode\"|" "$CONF_FILE"
    info "Modo alterado para: ${BOLD}$new_mode${NC}"

    # Atualizar países se um preset foi selecionado
    if [[ -n "$apply_preset" ]]; then
        local preset_countries="${PRESETS[$apply_preset]}"
        sed -i "s|^COUNTRIES=.*|COUNTRIES=\"$preset_countries\"|" "$CONF_FILE"
        local cc_count
        cc_count=$(echo "$preset_countries" | wc -w)
        info "Preset '$apply_preset' aplicado ($cc_count países)."
    fi

    # Verificar se o config foi salvo corretamente
    local saved_mode saved_countries
    saved_mode=$(grep "^MODE=" "$CONF_FILE" | cut -d'"' -f2)
    saved_countries=$(grep "^COUNTRIES=" "$CONF_FILE" | cut -d'"' -f2)
    echo ""
    echo -e "  ${BOLD}Config salvo:${NC}"
    echo -e "  Modo:     ${CYAN}$saved_mode${NC}"
    echo -e "  Países:   ${CYAN}$(echo "$saved_countries" | wc -w) países${NC}"
    echo -e "  Arquivo:  ${CYAN}$CONF_FILE${NC}"

    # ── 2. Limpar whitelist se mudou para blacklist ─────────
    if [[ "$new_mode" == "blacklist" && -f "$WHITELIST_FILE" ]]; then
        local removed_count
        removed_count=$(grep -cE '\|(domain|cidr)\|' "$WHITELIST_FILE" 2>/dev/null || echo 0)
        if [[ "$removed_count" -gt 0 ]]; then
            sed -i '/|domain|/d;/|cidr|/d' "$WHITELIST_FILE"
            info "Removidas $removed_count entradas de domínios/CIDRs (desnecessárias em blacklist)."
        fi
    fi

    # ── 3. Atualizar cron ──────────────────────────────────
    echo ""
    step "Atualizando cron..."
    setup_cron

    # ── 4. Atualizar listas GeoIP ──────────────────────────
    echo ""
    step "Atualizando listas GeoIP..."
    if command -v geoip-fw &>/dev/null; then
        geoip-fw update 2>&1 | tail -3
    else
        warn "geoip-fw não encontrado. Execute manualmente: geoip-fw update"
    fi

    # ── 5. Aplicar regras ──────────────────────────────────
    echo ""
    step "Aplicando regras do firewall..."
    if command -v geoip-fw &>/dev/null; then
        geoip-fw reload 2>&1 | tail -5
    else
        warn "geoip-fw não encontrado. Execute manualmente: geoip-fw reload"
    fi

    # ── 6. Resumo final ───────────────────────────────────
    echo ""
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}   ✔ Modo alterado com sucesso!${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Modo:     ${BOLD}$saved_mode${NC}"
    echo -e "  Países:   ${BOLD}$(echo "$saved_countries" | wc -w)${NC}"
    echo ""
    if [[ "$new_mode" == "blacklist" ]]; then
        echo -e "  ${YELLOW}Países bloqueados:${NC}"
        echo "  $saved_countries" | fold -s -w 60 | sed 's/^/    /'
    else
        echo -e "  ${YELLOW}Países permitidos:${NC}"
        echo "  $saved_countries" | fold -s -w 60 | sed 's/^/    /'
    fi
    echo ""
    echo -e "  ${BOLD}Dica:${NC} Execute ${CYAN}geoip-fw check${NC} para verificação completa."
    echo ""
}

# ── Opção 11: Reinstalar / Reparar ────────────────────────
menu_repair() {
    echo ""
    echo -e "${BOLD}═══ Reinstalar / Reparar ═══${NC}"
    echo ""
    echo "  1) Reparar instalação (mantém configurações)"
    echo "     Reinstala os componentes faltando, preserva config.conf e whitelist.conf"
    echo ""
    echo "  2) Reinstalação completa (apaga tudo e recomeça)"
    echo "     Remove tudo e roda o instalador do zero"
    echo ""
    echo "  0) Voltar"
    echo ""
    ask "Escolha: "
    read -r sub
    case "$sub" in
        1)
            echo ""
            warn "Reparando instalação — configurações serão preservadas..."
            echo ""
            detect_os
            detect_firewall
            check_connectivity
            install_dependencies
            [[ ! -d "$GEOIP_SHELL_DIR" ]] && install_geoip_shell
            install_wrapper
            setup_cron
            update_default_entries
            # Sincronizar domínios/CIDRs após atualizar entradas padrão
            if [[ -f "$DOMAINS_FILE" ]] && command -v geoip-fw &>/dev/null; then
                geoip-fw domain sync 2>/dev/null || true
            fi
            if [[ -f "$CIDR_SOURCES_FILE" ]] && command -v geoip-fw &>/dev/null; then
                geoip-fw cidr sync 2>/dev/null || true
            fi
            echo ""
            info "Reparo concluído."
            ;;
        2)
            echo ""
            warn "ATENÇÃO: Isso vai remover TODA a configuração e reinstalar do zero."
            ask "Tem certeza? [s/N]: "
            read -r confirm
            if [[ "${confirm,,}" == "s" ]]; then
                geoip-fw uninstall 2>/dev/null || true
                run_fresh_install
            fi
            ;;
        0) return ;;
        *) warn "Opção inválida." ;;
    esac
}

# ── Instalação parcial detectada ──────────────────────────
handle_partial_install() {
    echo ""
    echo -e "${YELLOW}${BOLD}⚠ Instalação incompleta detectada:${NC}"
    echo ""
    [[ -f "$CONF_FILE" ]]       \
        && echo -e "  ${GREEN}✔${NC} config.conf encontrado"    \
        || echo -e "  ${RED}✖${NC} config.conf NÃO encontrado"
    [[ -x "$WRAPPER_BIN" ]]     \
        && echo -e "  ${GREEN}✔${NC} geoip-fw encontrado"       \
        || echo -e "  ${RED}✖${NC} geoip-fw NÃO encontrado"
    [[ -d "$GEOIP_SHELL_DIR" ]] \
        && echo -e "  ${GREEN}✔${NC} geoip-shell encontrado"    \
        || echo -e "  ${RED}✖${NC} geoip-shell NÃO encontrado"
    echo ""
    echo "  1) Reparar automaticamente (preserva configurações existentes)"
    echo "  2) Reinstalação completa"
    echo "  0) Sair"
    echo ""
    ask "Escolha: "
    read -r choice
    case "$choice" in
        1)
            detect_os
            detect_firewall
            check_connectivity
            install_dependencies
            install_geoip_shell
            install_wrapper
            setup_cron
            if [[ ! -f "$CONF_FILE" ]]; then
                warn "config.conf não encontrado — iniciando assistente de configuração..."
                wizard
                generate_configs
                apply_initial_config
            fi
            update_default_entries
            # Sincronizar domínios após reparo
            if [[ -f "$DOMAINS_FILE" ]] && command -v geoip-fw &>/dev/null; then
                geoip-fw domain sync 2>/dev/null || true
            fi
            # Sincronizar CIDRs após reparo
            if [[ -f "$CIDR_SOURCES_FILE" ]] && command -v geoip-fw &>/dev/null; then
                geoip-fw cidr sync 2>/dev/null || true
            fi
            echo ""
            info "Reparo concluído."
            ;;
        2) run_fresh_install ;;
        0) exit 0 ;;
        *) warn "Opção inválida."; exit 1 ;;
    esac
}

# ── Menu principal (pós-instalação) ───────────────────────
show_main_menu() {
    while true; do
        clear
        echo -e "${BLUE}${BOLD}"
        echo "  ╔══════════════════════════════════════════╗"
        echo "  ║   GeoIP Firewall — AMS SOFT              ║"
        echo "  ║         www.amssoft.com.br  v1.0.0           ║"
        echo "  ╚══════════════════════════════════════════╝"
        echo -e "${NC}"

        show_current_summary

        echo -e "  ${BOLD}O que deseja fazer?${NC}"
        echo ""
        echo "   1) Liberar um IP (whitelist)"
        echo "   2) Bloquear um IP permanentemente"
        echo "   3) Gerenciar países permitidos"
        echo "   4) Gerenciar países bloqueados"
        echo "   5) Ver IPs liberados/bloqueados"
        echo "   6) Domínios/APIs (whitelist automático)"
        echo "   7) Redes confiáveis (Cloudflare, Fastly...)"
        echo "   8) Verificar saúde do sistema"
        echo "   9) Atualizar listas GeoIP"
        echo "  10) Alterar modo de operação (whitelist/blacklist)"
        echo "  11) Reinstalar / Reparar"
        echo "  12) Remover tudo"
        echo ""
        # Opções de estado do firewall — label dinâmico
        # NOTA: não usar grep -q com pipe — causa SIGPIPE no iptables com set -euo pipefail
        local _fw_st
        if iptables -t mangle -L GEOIP-SHELL_IN -n 2>/dev/null | grep "DROP\|ACCEPT" >/dev/null 2>&1; then
            _fw_st="active"
        elif crontab -l 2>/dev/null | grep -q "geoip-shell-persistence"; then
            _fw_st="paused"
        else
            _fw_st="disabled"
        fi
        if [[ "$_fw_st" == "active" ]]; then
            echo "  13) Pausar firewall (temporário — regras voltam no reboot)"
            echo "  14) Desativar firewall (permanente — até reativar manualmente)"
        else
            echo -e "  13) ${GREEN}Reativar firewall${NC}"
            echo "  14) Desativar firewall (permanente — até reativar manualmente)"
        fi
        echo "   0) Sair"
        echo ""
        ask "Escolha: "
        read -r choice

        case "$choice" in
            1) menu_whitelist_ip ;;
            2) menu_blacklist_ip ;;
            3) menu_manage_countries "allow" ;;
            4) menu_manage_countries "block" ;;
            5) menu_view_lists ;;
            6) menu_domains ;;
            7) menu_cidr ;;

            8)
                echo ""
                geoip-fw check || true
                echo ""
                ask "Pressione ENTER para voltar ao menu..."
                read -r
                continue
                ;;
            9)
                echo ""
                step "Atualizando listas GeoIP..."
                geoip-fw update || true
                ;;
            10) menu_change_mode ;;
            11) menu_repair ;;
            12)
                echo ""
                warn "ATENÇÃO: Isso vai remover completamente o GeoIP Firewall."
                ask "Tem certeza? [s/N]: "
                read -r confirm
                [[ "${confirm,,}" == "s" ]] && { geoip-fw uninstall || true; exit 0; }
                ;;
            13)
                echo ""
                if iptables -t mangle -L GEOIP-SHELL_IN -n 2>/dev/null | grep "DROP\|ACCEPT" >/dev/null 2>&1; then
                    geoip-fw pause || true
                else
                    geoip-fw enable || true
                fi
                ;;
            14)
                echo ""
                geoip-fw disable || true
                ;;
            0)
                echo ""
                info "Saindo."
                exit 0
                ;;
            *) warn "Opção inválida." ;;
        esac

        echo ""
        ask "Pressione ENTER para voltar ao menu..."
        read -r
    done
}

# ── Atualizar entradas padrão nos arquivos de configuração ─
update_default_entries() {
    local updated=0

    # ── domains.conf ────────────────────────────────────────
    if [[ -f "$DOMAINS_FILE" ]]; then
        local default_domains=(
            "api.mercadopago.com|MercadoPago — callback/IPN
elb-tl-mercadopago-1-520111085.us-east-1.elb.amazonaws.com|MercadoPago — ELB webhook us-east-1"
            "ipnpb.paypal.com|PayPal — IPN"
            "api.stripe.com|Stripe — webhooks"
            "ws.pagseguro.uol.com.br|PagSeguro — notificações"
            "api.cielo.com.br|Cielo — API pagamentos"
            "api.gerencianet.com.br|Gerencianet/Efí — callback"
            "api.efipay.com.br|Efí Pay — callback"
            "api.asaas.com|Asaas — webhook"
            "api.iugu.com|iugu — callback"
            "api.pagar.me|Pagar.me — webhook"
            "api.userede.com.br|Rede — API pagamentos"
            "checkout.hotmart.com|Hotmart — notificação de venda"
            "api.appmax.com.br|Appmax — webhook"
            "a.licensing.whmcs.com|WHMCS — validação de licença (semanal)"
            "releases.whmcs.com|WHMCS — verificação de atualizações"
            "api.namecheap.com|Namecheap — registro de domínios"
            "api.enom.com|eNom — registro de domínios"
            "rr-n1-tor.opensrs.net|OpenSRS — registro de domínios"
            "api.internet.bs|Internet.bs — registro de domínios"
            "api.resellerclub.com|ResellerClub/LogicBoxes — registro de domínios"
            "minfraud.maxmind.com|MaxMind minFraud — pontuação antifraude"
            "a.licensing.cpanel.net|cPanel — validação de licença"
            "verify.cpanel.net|cPanel — verificação de licença"
        )
        for entry in "${default_domains[@]}"; do
            local domain="${entry%%|*}"
            if ! grep -qF "${domain}|" "$DOMAINS_FILE" 2>/dev/null; then
                echo "$entry" >> "$DOMAINS_FILE"
                updated=$((updated + 1))
            fi
        done
    fi

    # ── cidr-sources.conf (cria se não existir) ──────────────
    if [[ ! -f "$CIDR_SOURCES_FILE" ]]; then
        mkdir -p "$CONF_DIR"
        cat > "$CIDR_SOURCES_FILE" << 'CIDR_HEADER_EOF'
# ============================================================
#  GeoIP Firewall — Fontes de CIDR confiáveis por URL
#  AMS SOFT (www.amssoft.com.br)
#
#  Formato: url|descrição
#  A URL deve retornar texto plano com um IP/CIDR por linha.
#
#  Para gerenciar via CLI:
#    geoip-fw cidr add https://example.com/ips "CDN XYZ"
#    geoip-fw cidr remove https://example.com/ips
#    geoip-fw cidr list
#    geoip-fw cidr sync   (força re-download)
# ============================================================

# ── CDNs / Infraestrutura confiável ──────────────────────
CIDR_HEADER_EOF
        info "cidr-sources.conf criado em $CIDR_SOURCES_FILE"
    fi
    local default_cidrs=(
        "https://www.cloudflare.com/ips-v4|Cloudflare IPv4 — CDN (Stripe, MercadoPago, APIs)"
        "https://www.cloudflare.com/ips-v6|Cloudflare IPv6 — CDN (Stripe, MercadoPago, APIs)"
        "https://api.fastly.com/public-ip-list|Fastly — CDN (GitHub, npm, SaaS)"
    )
    for entry in "${default_cidrs[@]}"; do
        local url="${entry%%|*}"
        if ! grep -qF "${url}|" "$CIDR_SOURCES_FILE" 2>/dev/null; then
            echo "$entry" >> "$CIDR_SOURCES_FILE"
            updated=$((updated + 1))
        fi
    done

    [[ $updated -gt 0 ]] && info "Entradas padrão adicionadas: $updated novas"
    return 0
}

# ── Fluxo de instalação (primeira vez) ────────────────────
run_fresh_install() {
    detect_os
    detect_firewall
    check_connectivity

    wizard

    install_dependencies
    install_geoip_shell
    generate_configs
    install_wrapper
    setup_cron
    apply_initial_config

    # Sincronizar domínios/APIs com whitelist
    if [[ -f "$DOMAINS_FILE" ]] && command -v geoip-fw &>/dev/null; then
        step "Sincronizando domínios/APIs com whitelist..."
        geoip-fw domain sync 2>&1 | grep -E "(✔|⚠|✖)" || true
    fi

    # Sincronizar CIDRs confiáveis (Cloudflare, etc.)
    if [[ -f "$CIDR_SOURCES_FILE" ]] && command -v geoip-fw &>/dev/null; then
        step "Sincronizando CIDRs confiáveis (Cloudflare, etc.)..."
        geoip-fw cidr sync 2>&1 | grep -E "(✔|⚠|✖)" || true
    fi

    final_report
}

# ═══════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════

main() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   GeoIP Firewall Installer — AMS SOFT   ║"
    echo "  ║         www.amssoft.com.br  v1.0.0           ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root

    local state
    state=$(check_installation_state)

    case "$state" in
        complete) show_main_menu ;;
        partial)  handle_partial_install ;;
        *)        run_fresh_install ;;
    esac
}

main "$@"

