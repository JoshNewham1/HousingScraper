# Housing Scraper

A housing scraper that checks Gumtree and Rightmove periodically and sends an email update with new/updated properties, designed to run as a serverless Docker container.

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
   
   The application supports multiple instances, each with its own configuration. Set up a shared configuration and one or more instance configurations:
   
   **Shared configuration** (used by all instances):
   ```bash
   cp .env.shared.example .env.shared
   ```
   Fill in your Mailjet credentials:
   - `MJ_APIKEY_PUBLIC`: Your Mailjet API Public Key.
   - `MJ_APIKEY_PRIVATE`: Your Mailjet API Private Key.
   - `SENDER_EMAIL`: Your verified Mailjet sender email.
   
   **Instance configuration** (one per search profile):
   ```bash
   cp .env.instance.example .env.my-search
   ```
   Fill in your search details:
   - `GUMTREE_LINK`: Your specific Gumtree search URL.
   - `RIGHTMOVE_LINK`: Your specific Rightmove search URL.
   - `RECIPIENT_EMAIL`: Where you want to receive notifications (supports semicolon-delimited addresses).
   - `START_DATE_FILTER`: (Optional) Only receive listings from this date onwards. Leave blank for all.
   - `SCHEDULE`: (Optional) Cron expression for when to run (defaults to `cron(0 9 * * ? *)` which is 9am UTC daily).
   
   You can create multiple instance files (e.g. `.env.london-search`, `.env.manchester-search`) to run different searches simultaneously.

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
   Create your shared and instance configuration files (see [Setup](#setup) above). The deployment script will automatically pick them up.

2. **Initialise Infrastructure**:
   ```bash
   terraform init
   ```

3. **Deploy (Infrastructure + Image)**:
   Run the deployment script:
   ```bash
   ./deploy.sh
   ```
   *The script automatically generates a `terraform.tfvars` from your `.env.shared` and `.env.<name>` files, runs `terraform apply`, and pushes your Docker image to ECR.*

4. **Verify**:
   - Check the **Elastic Container Service's Scheduled Tasks** to see the rules for each instance (named `housing-scraper-<instance>-scrape`).
   - Check **CloudWatch Logs** (one log group per instance at `/ecs/housing-scraper/<instance>`) to monitor execution.

### Managing Multiple Instances

To add a new search profile after deployment:

1. Create a new instance config file:
   ```bash
   cp .env.instance.example .env.another-search
   ```
   
2. Re-run deployment:
   ```bash
   ./deploy.sh
   ```
   
Terraform will create only the new per-instance resources (task definition, scheduled rule, log group, EFS access point) without recreating shared infrastructure. You can run different searches on different schedules simultaneously.

### Persistence in the Cloud
The application uses a shared EFS volume for persistent storage across task runs. Each instance has its own isolated data directory at `/data/<instance-name>`, so multiple instances can run independently without interfering with each other's state. This ensures that `housing.json` is preserved even when Fargate tasks terminate, preventing duplicate notifications per instance.

## Architecture

- **Node.js 20**: Core runtime.
- **Puppeteer**: Headless browser for scraping.
- **node-mailjet**: Email delivery.
- **Deep-Object-Diff**: Intelligent change detection.
