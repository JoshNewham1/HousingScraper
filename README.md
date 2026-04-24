# Housing Scraper (Dockerized)

A modern Node.js housing scraper for Gumtree and Rightmove, migrated from Azure Functions to a standalone containerized service.

## Features

- **Automated Scraping**: Scrapes Rightmove and Gumtree for new properties based on your search criteria.
- **Change Detection**: Compares current results with previous ones to find new or updated listings.
- **Execution**: Run it once to scrape and notify; ideal for external scheduling (e.g., system cron, Kubernetes CronJob).
- **Email Notifications**: Sends detailed HTML emails with images and property details.
- **Dockerized**: Easy deployment using Docker and Docker Compose.

## Prerequisites

- Docker and Docker Compose
- A Mailjet account with API keys and a verified sender email.

## Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd AzureHousingScraper
   ```

2. **Configure Environment Variables**:
   Copy `.env.example` to `.env` and fill in your details:
   ```bash
   cp .env.example .env
   ```
   - `GUMTREE_LINK`: Your specific Gumtree search URL.
   - `RIGHTMOVE_LINK`: Your specific Rightmove search URL.
   - `MJ_APIKEY_PUBLIC`: Your Mailjet API Public Key.
   - `MJ_APIKEY_PRIVATE`: Your Mailjet API Private Key.
   - `SENDER_EMAIL`: Your verified Mailjet sender email.
   - `RECIPIENT_EMAIL`: Where you want to receive notifications.

3. **Run with Docker Compose**:
   ```bash
   docker-compose up
   ```
   *Note: The container will exit after completing the scrape.*

## External Scheduling

Since the application is now a run-once script, you can schedule it using an external tool.

### Example System Cron
To run every day at 9 AM and 6 PM:
```bash
0 9,18 * * * cd /path/to/AzureHousingScraper && /usr/local/bin/docker-compose up
```

## Local Development

If you want to run the application locally without Docker:

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Build the project**:
   ```bash
   npm run build
   ```

3. **Start the service**:
   ```bash
   npm start
   ```

For development with hot-reload:
```bash
npm run dev
```

## Data Persistence

The application stores the latest scraping results in `data/housing.json`. When running with Docker Compose, this file is persisted in a local `data` directory mapped as a volume.

## Architecture

- **Node.js 20**: Core runtime.
- **Puppeteer**: Headless browser for scraping.
- **node-mailjet**: Email delivery.
- **Deep-Object-Diff**: Intelligent change detection.
