# Housing Scraper

A TypeScript housing scraper that checks Gumtree and Rightmove periodically and sends an email update with new/updated properties, designed to run as a serverless Docker container.

## Features

- **Automated Scraping**: Scrapes Rightmove and Gumtree for new properties based on your search criteria.
- **Change Detection**: Compares current results with previous ones to find new or updated listings.
- **Email Notifications**: Sends update emails with images and property details.
- **Dockerised**: Easy deployment using Docker and Docker Compose.

## Prerequisites

- Docker and Docker Compose
- A Mailjet account with API keys and a verified sender email.

## Setup

1. **Clone the repository**:
   ```bash
   git clone git@github.com:JoshNewham1/HousingScraper.git
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
   docker compose up --build
   ```
   *Note: The container will exit after completing the scrape.*

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

## Cloud Deployment (AWS)

We provide a Terraform file for deployment to AWS using **ECS Fargate** and **EFS** for persistent storage. It is designed to run once daily at 9:00 AM UTC to stay within the AWS Free Tier.

### Prerequisites
- [Terraform](https://www.terraform.io/downloads.html) installed.
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured with appropriate credentials (`aws login`).
- Docker installed and running.

### Deployment Steps

1. **Configure Environment Variables**:
   Ensure your `.env` file is fully populated. These values will be automatically uploaded to the AWS ECS task.

2. **Initialise Infrastructure**:
   ```bash
   terraform init
   ```

3. **Deploy (Infrastructure + Image)**:
   Run the deployment script:
   ```bash
   ./deploy.sh
   ```
   *The script automatically generates a `terraform.tfvars` from your `.env`, runs `terraform apply`, and pushes your Docker image to ECR.*

4. **Verify**:
   - Check the **Elastic Container Service's Scheduled Tasks** to see/modify the schedule (`housing-scraper-daily-scrape`).
   - Check **CloudWatch Logs** (`/ecs/housing-scraper`) to monitor execution.

### Persistence in the Cloud
The application is configured to mount an EFS volume at `/app/data`. This ensures that `housing.json` is preserved even when the Fargate task terminates, preventing duplicate notifications.

## Architecture

- **Node.js 20**: Core runtime.
- **Puppeteer**: Headless browser for scraping.
- **node-mailjet**: Email delivery.
- **Deep-Object-Diff**: Intelligent change detection.
