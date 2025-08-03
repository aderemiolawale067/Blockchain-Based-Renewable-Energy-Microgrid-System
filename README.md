# Blockchain-Based Renewable Energy Microgrid System

A decentralized community power system built on Stacks blockchain using Clarity smart contracts.

## Overview

This system enables communities to create resilient, sustainable energy networks through five interconnected smart contracts:

1. **Energy Generation Tracking** - Monitor renewable energy production
2. **Peer-to-Peer Energy Trading** - Direct energy marketplace
3. **Smart Load Balancing** - Optimize energy consumption
4. **Battery Storage Coordination** - Manage community storage
5. **Resilience Management** - Emergency protocols and disaster response

## Architecture

### Core Contracts

- `energy-generation.clar` - Tracks solar panels, wind turbines, and other renewable sources
- `p2p-energy-trading.clar` - Facilitates direct energy trading between community members
- `load-balancing.clar` - Manages smart appliance scheduling and load optimization
- `battery-storage.clar` - Coordinates individual and community battery systems
- `resilience-management.clar` - Handles emergency protocols and critical infrastructure

### Key Features

- **Decentralized Energy Trading** - Community members can buy and sell energy directly
- **Smart Grid Optimization** - Automatic load balancing based on renewable availability
- **Emergency Resilience** - Prioritized power allocation during outages
- **Transparent Governance** - All transactions recorded on blockchain
- **Economic Incentives** - Rewards for grid-stabilizing behaviors

## Quick Start

### Installation

```bash
# Clone repository
git clone https://github.com/community/renewable-energy-microgrid
cd renewable-energy-microgrid

# Install dependencies
npm install

# Run tests
npm test

# Check contracts
clarinet check
