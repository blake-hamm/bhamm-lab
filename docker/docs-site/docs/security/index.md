# Security

*Homelab security framework with current tools and future roadmap while preparing for exposure*


## Security Stack Layers
### Network Security
- **Current**: Basic firewall rules
- **Future**: CrowdSec integration, IDS/IPS, Cilium policies

### Access Control
- **Current**: SSH keys, basic RBAC, LLDAP, MFA with Authelia/Traefik
- **Future**: Wireguard VPN, advanced RBAC, alerting, consider Keycloak

### Secrets Management
- **Current**: SOPS + Vault
- **Future**: Automated rotation

### Application Security
- **Current**: Manual updates
- **Future**: Automated vulnerability scanning and renovate bot

### Monitoring & Auditing
- **Current**: Basic logs
- **Future**: SIEM integration, CrowdSec alerts

## Future Roadmap
1. **Service Exposure Framework**:
    - Secure reverse proxy setup
    - CrowdSec for threat prevention
    - Split DNS for internal/external services

2. **Compliance Automation**:
    - Scheduled vulnerability scans
    - Renovate bot image updates
    - Policy-as-code implementation

## Reference
- 🔐 [SOPS](sops.md) - Secrets encryption
- 🗄️ [Vault](vault.md) - Secrets management
