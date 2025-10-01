# ⚖️ Decentralized Dispute Mediation System

A blockchain-based dispute resolution platform where neutral arbitrators resolve conflicts using community-selected jurors and transparent voting mechanisms.

## 🌟 Features

- **🏛️ Decentralized Arbitration**: Community-driven dispute resolution
- **👥 Juror Selection**: Random selection from registered juror pool
- **🗳️ Transparent Voting**: Public voting system with time limits
- **💰 Secure Payments**: Automated payment distribution based on outcomes
- **📊 Arbitrator Ratings**: Track arbitrator performance and success rates
- **🔐 Emergency Controls**: Contract owner can resolve disputes in emergencies

## 🚀 Quick Start

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation
```bash
git clone <repository-url>
cd Decentralized-Dispute-Mediation-System
clarinet check
```

## 📖 Usage Guide

### 1. 👨‍⚖️ Register as Juror
```clarity
(contract-call? .Decentralized-Dispute-Mediation-System register-as-juror)
```

### 2. 📋 Create Dispute
```clarity
(contract-call? .Decentralized-Dispute-Mediation-System create-dispute 
  'SP2... ; defendant address
  'SP3... ; arbitrator address
  u"Description of the dispute") ; dispute description
```

### 3. 🗳️ Cast Vote (Jurors Only)
```clarity
(contract-call? .Decentralized-Dispute-Mediation-System cast-vote 
  u1     ; dispute ID
  true)  ; vote (true = for plaintiff, false = for defendant)
```

### 4. ⚖️ Resolve Dispute (Arbitrator Only)
```clarity
(contract-call? .Decentralized-Dispute-Mediation-System resolve-dispute u1)
```

## 🔧 Configuration

### Contract Parameters
- **Dispute Fee**: 1,000,000 microSTX (1 STX) - adjustable by contract owner
- **Voting Duration**: 144 blocks (~24 hours) - adjustable by contract owner
- **Minimum Votes**: 3 votes required for resolution
- **Juror Pool**: 5 jurors selected per dispute

### Admin Functions
```clarity
; Set new dispute fee
(contract-call? .Decentralized-Dispute-Mediation-System set-dispute-fee u2000000)

; Set new voting duration
(contract-call? .Decentralized-Dispute-Mediation-System set-voting-duration u288)

; Emergency dispute resolution
(contract-call? .Decentralized-Dispute-Mediation-System emergency-resolve u1 "plaintiff")
```

## 📊 Read-Only Functions

### Get Dispute Information
```clarity
(contract-call? .Decentralized-Dispute-Mediation-System get-dispute u1)
```

### Check Juror Status
```clarity
(contract-call? .Decentralized-Dispute-Mediation-System is-juror 'SP1...)
```

### View Arbitrator Rating
```clarity
(contract-call? .Decentralized-Dispute-Mediation-System get-arbitrator-rating 'SP1...)
```

### Contract Stats
```clarity
(contract-call? .Decentralized-Dispute-Mediation-System get-contract-balance)
(contract-call? .Decentralized-Dispute-Mediation-System get-juror-pool-size)
(contract-call? .Decentralized-Dispute-Mediation-System get-dispute-fee)
```

## 🔄 Dispute Lifecycle

1. **📝 Creation**: Plaintiff creates dispute with fee payment
2. **👥 Juror Selection**: 5 jurors randomly selected from pool
3. **🗳️ Voting Period**: 144 blocks for jurors to cast votes
4. **⚖️ Resolution**: Arbitrator resolves based on majority vote
5. **💰 Payment**: Funds distributed to winning party

## 🛡️ Security Features

- ✅ Access control for arbitrators and jurors
- ✅ Time-limited voting periods
- ✅ Duplicate vote prevention
- ✅ Emergency resolution capabilities
- ✅ Balance and payment validation

## 🧪 Testing

```bash
clarinet test
```

## 📋 Error Codes

- `u100`: Unauthorized access
- `u101`: Dispute not found
- `u102`: Invalid dispute status
- `u103`: Insufficient payment
- `u104`: Already voted
- `u105`: Not a registered juror
- `u106`: Dispute expired

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Clarinet Documentation](https://github.com/hirosystems/clarinet)
