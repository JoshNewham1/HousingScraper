import dns from "dns/promises";
import { Page } from "puppeteer";

export type Property = {
  address: string,
  type: string,
  link: string,
  bedrooms: number,
  pricePerMonth : number,
  pricePerMonthPerPerson: number,
  pricePerWeek: number,
  image: string,
  availableDate: string,
  furnished: string,
  councilTax: string | undefined;
  concierge: string;
  agent: string,
}

export async function hasInternetConnection(): Promise<boolean> {
  try {
    await dns.resolve("rightmove.co.uk");
    return true;
  } catch {
    return false;
  }
}

export const delay = (delayMs: number) => {
  return new Promise<void>((res, _) => {
    setTimeout(() => res(), delayMs);
  });
};

// Scroll down the page by the height of the window until we reach the bottom
// Delay by 100ms to give content time to start loading
export const autoScroll = async (page: Page) => {
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
};

// Format the email HTML from the properties object
export const buildEmailHtml = (properties: Record<string, Property>, subtitle: string) => {
  let emailHtml = `<h2>${subtitle}</h2>`;
  Object.keys(properties).forEach((key) => {
    emailHtml += `
    <div style="margin-bottom: 25px;">
      <a href="${properties[key]["link"]}">Link</a> <br/>
      <img src="${properties[key]["image"]}" width="200">
    `;

    (Object.keys(properties[key]) as (keyof Property)[]).forEach((detail) => {
      if (detail === "link" || detail === "pricePerWeek" || detail === "image") {
        // Skip link and weekly price attribs
        return;
      } else if (detail == "pricePerMonth" || detail === "pricePerMonthPerPerson") {
        emailHtml += `<p><b>${detail}:</b> £${properties[key][detail].toFixed(2)}</p>`;
      } else if (detail === "availableDate" && new Date(properties[key][detail])) {
        emailHtml += `<p><b>${detail}:</b> ${new Date(properties[key][detail]).toLocaleDateString("en-GB")}</p>`;
      } else {
        emailHtml += `<p><b>${detail}:</b> ${properties[key][detail]}</p>`;
      }
    });

    emailHtml += "</div><hr>";
  });
  return emailHtml;
};
