import * as puppeteer from "puppeteer";
import { delay } from "./utils";

export const scrapeRightMove = async () => {
  const startingUrl = process.env["RIGHTMOVE_LINK"];
  if (!startingUrl) {
    throw new Error("RIGHTMOVE_LINK environment variable is not set");
  }

  const browser = await puppeteer.launch({
    headless: true,
    executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || undefined,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
    timeout: 0,
  });

  try {
    const page = await browser.newPage();
    console.log("Launched puppeteer for Rightmove");
    await page.setUserAgent(
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.5005.61 Safari/537.36"
    );
    await page.goto(startingUrl);
    await page.waitForSelector(".propertyCard-details");
    // Add jQuery to the page so we can use it for selectors
    // Note: this only needs to be done once for Rightmove as it uses AJAX and doesn't load any new pages
    await page.addScriptTag({
      url: "https://code.jquery.com/jquery-3.3.1.slim.min.js",
    });
    // Get the number of pages in the pagination element at the bottom
    const numPages = await page.evaluate(() => {
      const el =  document.querySelector('[class*="Pagination_paginationContainer"] > div > span:nth-child(3)')?.innerHTML?.split("-->")[1];
      return el ? parseInt(el) : 1;
    });
    console.log(`${numPages} pages found on Rightmove website`);
    let properties: any = {};
    for (let i = 1; i <= numPages; i++) {
      const thisPage = await page.evaluate(async () => {
        const results = await Promise.all(
          $(".propertyCard-details")
            .map(async function () {
              // Scrape all the content from HTML elements on the page
              const link =
                "https://www.rightmove.co.uk" +
                $(this).find(".propertyCard-link").attr("href");

              // "Click into" the property to get more metadata
              // Note: using fetch inside evaluate might have CORS issues if not handled, 
              // but in original code it was used.
              const metadata = await fetch(link).then((res) => res.text());

              const address = $(this).find("address").text().trim();

              const type =
                // Property type (flat or house)
                $(this)
                  .find(".propertyCard-link > div > div > span:nth-child(1)")
                  .text()
                  .trim();

              const bedroomsText = $(this)
                  .find('[class*="PropertyInformation_bedroomsCount"]')
                  .text();
              const bedrooms = parseInt(bedroomsText) || 1;

              const priceText = $(this)
                    .find('[class*="PropertyPrice_price_"]')
                    .text()
                    .trim()
                    .match(/\d+/g);
              const pricePerMonth = priceText ? parseInt(priceText.join("")) : 0;

              const secondaryPriceText = $(this)
                    .find('[class*="PropertyPrice_secondaryPrice"]')
                    .text()
                    .trim()
                    .match(/\d+/g);
              const pricePerWeek = secondaryPriceText ? parseInt(secondaryPriceText[0]) : 0;

              const image = $(this)
                              .find('[class*="PropertyCardImageSwiper_propertyImagesWrapper"] > div > div:nth-child(1) > img:nth-child(1)')
                              .attr("src");

              const availableDate =
                // Use a nasty selector to get the available date text (it has no class or id)
                $(metadata)
                  .find(
                    "#main > div > div > div > article:nth-child(5) > div > dl > div:nth-child(1) > dd"
                  )
                  .text();

              const furnished = $(metadata)
                .find(
                  "#main > div > div > div > article:nth-child(5) > div > dl > div:nth-child(4) > dd"
                )
                .text();

              const agent =
                // Estate agent
                $(metadata)
                  .find(
                    '[data-testid="branchName"] > a'
                  )
                  .text();

              return {
                address,
                type,
                link,
                bedrooms,
                pricePerMonth,
                pricePerMonthPerPerson: (pricePerMonth / bedrooms).toFixed(2),
                pricePerWeek,
                image,
                availableDate,
                furnished,
                agent,
              };
            })
            .toArray()
        );
        return results;
      });
      console.log(
        `Rightmove: page ${i} scraped, ${thisPage.length} properties scraped`
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
        if (properties[compositeKey]) {
          console.log("Duplicate found:", compositeKey);
        }
        properties[compositeKey] = property;
      }
      
      if (i < numPages) {
        await page.evaluate(() => {
          (document.querySelector('[data-testid="nextPage"]') as HTMLButtonElement)?.click();
        });
        await delay(1000);
      }
    }
    return properties;
  } finally {
    await browser.close();
  }
};
