import * as puppeteer from "puppeteer";
import { delay, Property } from "./utils";

// Scroll down the page by the height of the window until we reach the bottom
// Delay by 100ms to give content time to start loading
const autoScroll = async (page: puppeteer.Page) => {
  await page.evaluate(async () => {
    await new Promise((resolve) => {
      let totalHeight = 0;
      const distance = 100;
      const timer = setInterval(() => {
        var scrollHeight = document.body.scrollHeight;
        window.scrollBy(0, distance);
        totalHeight += distance;

        if (totalHeight >= scrollHeight - window.innerHeight) {
          clearInterval(timer);
          resolve("");
        }
      }, 250);
    });
  });
  await delay(2000);
};

export const scrapeGumtree = async () => {
  const startingUrl = process.env["GUMTREE_LINK"];
  if (!startingUrl) {
    throw new Error("GUMTREE_LINK environment variable is not set");
  }

  const browser = await puppeteer.launch({
    headless: false,
    executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || undefined,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
    timeout: 0,
  });
  
  try {
    const page = await browser.newPage();
    console.log("Launched puppeteer for Gumtree");
    await page.setUserAgent(
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36"
    );
    await page.setViewport({ width: 1200, height: 800 });
    await page.goto(startingUrl, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("h1", { timeout: 30000 });

    // Get the number of pages in the pagination element at the bottom
    const numPages = await page.evaluate(() => {
      const pageTitle = document.querySelector('#content > .view-container > .container > [class*="css-"] > [class*="css-"] > h1')?.textContent;
      const numResults = parseInt(pageTitle?.split(" ")[0] || "0");
      const PAGE_SIZE = 25;
      return Math.ceil(numResults / PAGE_SIZE);
    });
    console.log(`${numPages} pages found on Gumtree website`);

    // Lazy load images
    await autoScroll(page);

    let properties: any = {};
    for (let i = 1; i <= numPages; i++) {
      // Add jQuery to the page so we can use it to more easily scrape elements
      await page.addScriptTag({
        url: "https://code.jquery.com/jquery-3.3.1.slim.min.js",
      });
      // Create an object with all the properties on the current page and their attributes
      const thisPage: Property[] = await page.evaluate(() => {
        const parseDate = (dateStr: string): string => {
          if (dateStr.split(" ").length !== 3) return dateStr;
          const [d, m, y] = dateStr.split(" ");
          return new Date(
            Number(y),
            new Date(`${m} 1, 2000`).getMonth(),
            Number(d)
          ).toISOString();
        };
        return $('[data-q="section-middle"] > div > [class$="-list"]')
          .map(function () {
            if ($(this).hasClass("ad-spot")) return;

            // Remove the miles distance from address
            const address = $(this).find('[data-q="tile-location"]').text().trim();

            const type =
              // Whether it's a house or a flat
              $(this)
                .find('.attributes-container > span:nth-child(3)')
                .text();

            const link =
              "https://www.gumtree.com" +
              $(this).find('[data-q="search-result-anchor"]').attr("href");

            const bedroomsText = $(this)
                  .find('.attributes-container > span:nth-child(4)')
                  .text()
                  .match(/\d+/);
            const bedrooms = bedroomsText ? parseInt(bedroomsText[0]) : 1;

            const priceText = $(this)
                  .find('[data-q="tile-price"]')
                  .text();
            const priceNum = priceText.replace(/[^\d]/g, '');
            const pricePerMonth = priceText.includes("pw") ? parseInt(priceNum || "") * 4 : parseInt(priceNum || "");

            const image = $(this).find("img").attr("src");

            const availableDateStr =
              // Date available text with "Date available: " stripped
              $(this)
                .find('.attributes-container > span:nth-child(3)')
                .text()
                .replace("Date available: ", "");
            const availableDate = parseDate(availableDateStr);

            return {
              address,
              type,
              link,
              bedrooms,
              // Get price value, strip any text and convert to integer
              pricePerMonth,
              pricePerMonthPerPerson: (pricePerMonth / bedrooms),
              pricePerWeek: (pricePerMonth / 4),
              image,
              availableDate,
              furnished: "Unknown",
              agent: "Gumtree",
            } as Property;
          })
          .toArray()
        }
      );
      const startDate = process.env.START_DATE_FILTER && new Date(process.env.START_DATE_FILTER);
      const filtered = thisPage.filter(p => !startDate || (new Date(p.availableDate) && new Date(p.availableDate) >= startDate));
      console.log(
        `Gumtree: page ${i} scraped, ${thisPage.length} properties scraped, ${filtered.length} filtered results`
      );

      // Add all entries from the page into object
      // using a composite key of address, agent, pricePerMonth and bedrooms
      // to be unique (as some properties change their URL daily)
      for (const property of thisPage) {
        const compositeKey =
          property.address +
          property.agent +
          property.pricePerMonth +
          property.bedrooms;
        properties[compositeKey] = property;
      }

      // Still pages left to go through
      if (i < numPages) {
        await page.goto(startingUrl + "&page=" + i);
      }
    }
    return properties;
  } finally {
    await browser.close();
  }
};
