# 🔒 AMS SOFT — GeoIP Firewall

Instalador e gerenciador automatizado de firewall GeoIP para servidores Linux. Bloqueie ou permita tráfego por país usando whitelist/blacklist, com proteção automática para domínios (gateways de pagamento, APIs, CDNs) e redes confiáveis (Cloudflare, Fastly, AWS, Google Cloud).

Baseado em [geoip-shell](https://github.com/friendly-bits/geoip-shell) + nftables/iptables.

---

## ✨ Funcionalidades

- **Whitelist/Blacklist por país** — permita ou bloqueie tráfego usando códigos ISO 3166-1
- **Presets de regiões** — América do Sul, MERCOSUL, Europa, Mundo Lusófono e mais
- **Whitelist por domínio** — resolução automática de DNS para APIs e gateways de pagamento
- **Redes confiáveis por URL** — sincroniza CIDRs da Cloudflare, Fastly, AWS, Google Cloud, GitHub, Oracle
- **Whitelist manual de IPs** — libere IPs específicos mesmo que o país esteja bloqueado
- **Bloqueio manual de IPs** — bloqueie IPs ou faixas CIDR permanentemente
- **Detecção automática de firewall** — identifica nftables, iptables, UFW, firewalld e fail2ban
- **Proteção contra lockout** — IP da sessão SSH é adicionado automaticamente à whitelist
- **Atualização automática via cron** — listas GeoIP, domínios e CIDRs atualizados periodicamente
- **CLI completa** — gerencie tudo via comando `geoip-fw` após a instalação

---

## 🖥️ Compatibilidade

**Testado em:**
- ✅ Debian 11 / 12
- ✅ Ubuntu 20.04 / 22.04 / 24.04
- ✅ Linux Mint
- ✅ Pop!_OS

**Compatível com (não testado pelo autor):**
- CentOS / RHEL 7+
- AlmaLinux / Rocky Linux
- Fedora

**Requisitos:**
- Acesso root (sudo)
- Conexão com a internet (para download de listas GeoIP)
- Pacotes: `curl`, `wget`, `git`, `jq`, `dnsutils` (instalados automaticamente)

---

## 📦 Instalação

### 1. Baixe o script

```bash
wget https://raw.githubusercontent.com/adrianomedina-amssoft/amssoft-geoip-firewall/main/geoip.sh
```

Ou clone o repositório:

```bash
git clone https://github.com/adrianomedina-amssoft/amssoft-geoip-firewall.git
cd amssoft-geoip-firewall
```

### 2. Dê permissão de execução

```bash
chmod +x geoip.sh
```

### 3. Execute como root

```bash
sudo ./geoip.sh
```

Ou diretamente com bash:

```bash
sudo bash geoip.sh
```

### 4. Siga o assistente interativo

Na primeira execução, o script exibe um wizard com 3 perguntas:

```
[1/3] Modo de operação:
  1) Whitelist — permite APENAS os países selecionados (recomendado)
  2) Blacklist — bloqueia APENAS os países selecionados

[2/3] Quais países/regiões?
  1) Somente Brasil (BR)
  2) América do Sul (BR AR UY PY BO PE CL CO VE EC ...)
  3) MERCOSUL (BR AR UY PY)
  ...

[3/3] Interface de rede:
  Auto-detectada: eth0
```

Após o wizard, o script instala automaticamente todas as dependências, configura o firewall e ativa o bloqueio GeoIP.

---

## 🛠️ Uso (após instalação)

Todas as operações são feitas via comando `geoip-fw`:

### Status e verificação

```bash
# Ver configuração atual e status do firewall
geoip-fw status

# Auditoria completa do sistema
geoip-fw check

# Testar se um IP seria bloqueado ou permitido
geoip-fw test-ip 8.8.8.8
```

### Gerenciar países

```bash
# Adicionar países à lista
geoip-fw add-country RU CN

# Remover países da lista
geoip-fw remove-country AR

# Adicionar região inteira por preset
geoip-fw add-continent europe

# Presets disponíveis:
#   brazil_only, south_america, mercosul, latin_america,
#   brazil_portugal, europe, north_america, portuguese_world
```

### Whitelist de IPs

```bash
# Liberar um IP ou faixa CIDR
geoip-fw whitelist add 65.21.100.50 "Servidor backup"
geoip-fw whitelist add 95.216.0.0/16 "Rede AS24940"

# Listar IPs na whitelist
geoip-fw whitelist list

# Remover IP da whitelist
geoip-fw whitelist remove 65.21.100.50
```

### Domínios/APIs (whitelist automática)

```bash
# Listar domínios configurados
geoip-fw domain list

# Adicionar um domínio
geoip-fw domain add api.exemplo.com "Minha API"

# Remover um domínio
geoip-fw domain remove api.exemplo.com

# Forçar re-resolução de todos os domínios
geoip-fw domain sync
```

### Redes confiáveis (CIDRs por URL)

```bash
# Listar fontes de CIDR configuradas
geoip-fw cidr list

# Adicionar uma fonte
geoip-fw cidr add https://example.com/ips "CDN XYZ"

# Remover uma fonte
geoip-fw cidr remove https://example.com/ips

# Forçar re-download de todas as listas
geoip-fw cidr sync
```

### Operações do firewall

```bash
# Reaplicar todas as regras (após mudanças no config)
geoip-fw reload

# Forçar atualização das listas GeoIP
geoip-fw update

# Pausar firewall temporariamente (volta no reboot)
geoip-fw pause

# Reativar firewall
geoip-fw enable

# Desativar firewall permanentemente
geoip-fw disable

# Remover tudo
geoip-fw uninstall
```

---

## 📁 Arquivos de configuração

Após a instalação, os arquivos ficam em `/etc/geoip-firewall/`:

| Arquivo | Descrição |
|---|---|
| `config.conf` | Configuração principal (modo, países, interface, ação de bloqueio) |
| `whitelist.conf` | IPs e faixas na whitelist (por tipo: auto, manual, session, domain, cidr) |
| `domains.conf` | Domínios para resolução automática de IPs |
| `cidr-sources.conf` | URLs de listas de CIDRs confiáveis |

**Formato do whitelist.conf:**
```
IP_OU_CIDR|tipo|descrição
10.0.0.0/8|auto|Rede privada RFC1918
65.21.100.50|manual|Servidor backup
```

**Formato do domains.conf:**
```
domínio|descrição
api.stripe.com|Stripe — webhooks
api.mercadopago.com|MercadoPago — callback
```

**Formato do cidr-sources.conf:**
```
url|descrição
https://www.cloudflare.com/ips-v4|Cloudflare IPv4 — CDN
```

---

## ⏰ Atualizações automáticas (Cron)

O script configura automaticamente as seguintes tarefas:

| Frequência | Tarefa |
|---|---|
| Toda segunda-feira às 04:15 | Atualização das listas GeoIP |
| A cada 6 horas | Re-resolução de domínios (DNS) |
| Diariamente às 02:00 | Re-download de listas de CIDRs |

---

## 🔧 Reinstalação e reparo

Se algo der errado, execute novamente o script:

```bash
sudo ./geoip.sh
```

Ele detectará a instalação existente e oferecerá:

- **Reparar** — reinstala componentes faltantes, preserva configurações
- **Reinstalação completa** — remove tudo e começa do zero

---

## 📝 Log

Todas as operações são registradas em:

```bash
cat /var/log/geoip-firewall.log
```

---

## 🤝 Créditos

- **Autor:** Adriano Medina — [AMS SOFT](https://www.amssoft.com.br)
- **Motor GeoIP:** [geoip-shell](https://github.com/friendly-bits/geoip-shell) por friendly-bits
- **Fontes de CIDR:** Cloudflare, Fastly, AWS, Google Cloud, GitHub, Oracle

---

## Apoie o Projeto ☕

Este módulo é gratuito e de código aberto. Se ele te ajudou a economizar tempo ou proteger melhor o seu servidor, considere fazer uma doação de qualquer valor para ajudar a manter o projeto vivo, financiar melhorias e novas funcionalidades.

Toda contribuição, por menor que seja, faz diferença. Muito obrigado! 🙏

| Método | Link |
|---|---|
| Mercado Pago | [Clique aqui para doar via Mercado Pago](https://www.mercadopago.com.br/subscriptions/checkout?preapproval_plan_id=95add4219a6b47f286b1405a51a39b7b) |
| PayPal | [Clique aqui para doar via PayPal](https://www.paypal.com/ncp/payment/UZQBBQ4BQ89UQ) |

---

## 📄 Licença

MIT License — uso livre para fins pessoais e comerciais.

Ao distribuir ou modificar este projeto, por favor mantenha os créditos:

```
Desenvolvido por Adriano Medina | AMS SOFT
https://www.amssoft.com.br
```
