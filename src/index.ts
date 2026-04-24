import * as dotenv from "dotenv";
dotenv.config();

import * as fs from "fs-extra";
import * as path from "path";
import { detailedDiff } from "deep-object-diff";
import { scrapeGumtree } from "./lib/gumtree";
import { scrapeRightMove } from "./lib/rightmove";
import { buildEmailHtml } from "./lib/utils";
import { sendEmail } from "./lib/email";

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "..", "data");
const HOUSING_JSON_PATH = path.join(DATA_DIR, "housing.json");

async function runScraper() {
  console.log(`[${new Date().toISOString()}] Starting housing scrape...`);
  try {
    // Ensure data directory exists
    await fs.ensureDir(DATA_DIR);

    // Load old properties
    let oldProperties = {};
    if (await fs.pathExists(HOUSING_JSON_PATH)) {
      try {
        oldProperties = await fs.readJson(HOUSING_JSON_PATH);
      } catch (e) {
        console.error("Error reading housing.json, starting with empty object", e);
      }
    }

    // Open Puppeteer and scrape
    const rightmoveProperties = await scrapeRightMove();
    const gumtreeProperties = await scrapeGumtree();
    const properties = { ...rightmoveProperties, ...gumtreeProperties };
    
    const propertiesDiff: any = detailedDiff(oldProperties, properties);
    console.log(`Object diff: ${JSON.stringify(propertiesDiff)}`);

    // Write file with all properties locally
    await fs.writeJson(HOUSING_JSON_PATH, properties, { spaces: 2 });
    console.log("Written JSON file locally successfully");

    // Check if there are any changes (added or updated)
    const hasAdded = propertiesDiff["added"] && Object.keys(propertiesDiff["added"]).length > 0;
    const hasUpdated = propertiesDiff["updated"] && Object.keys(propertiesDiff["updated"]).length > 0;

    if (!hasAdded && !hasUpdated) {
      console.log("No new or updated properties found.");
      return;
    }

    console.log("Changes detected, sending email...");

    const senderEmail = process.env["SENDER_EMAIL"];
    const recipientEmail = process.env["RECIPIENT_EMAIL"];

    if (!senderEmail || !recipientEmail) {
      throw new Error("SENDER_EMAIL or RECIPIENT_EMAIL environment variables are missing.");
    }

    let emailHtml = "<h1>Housing Updates</h1>";
    let numProperties = 0;
    
    if (hasAdded) {
      emailHtml += buildEmailHtml(propertiesDiff["added"], "Added Properties");
      numProperties = Object.keys(propertiesDiff["added"]).length;
    }
    if (hasUpdated) {
      emailHtml += buildEmailHtml(propertiesDiff["updated"], "Updated Properties");
    }

    await sendEmail({
      from: senderEmail,
      to: recipientEmail,
      subject: `Flat Search - ${numProperties} new properties`,
      html: emailHtml,
    });

    console.log("Email sent successfully");
  } catch (err) {
    console.error("Error during scraping process:", err);
    process.exit(1);
  }
}

// Execute the scraper immediately
runScraper();
