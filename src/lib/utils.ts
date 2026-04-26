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
  agent: string,
}

export const delay = (delayMs: number) => {
  return new Promise<void>((res, _) => {
    setTimeout(() => res(), delayMs);
  });
};

// Format the email HTML from the properties object
export const buildEmailHtml = (properties: Record<string, Property>, subtitle: string) => {
  let emailHtml = `<h2>${subtitle}</h2>`;
  Object.keys(properties).forEach((key) => {
    emailHtml += `
    <div style="margin-bottom: 25px;">
      <a href="${properties[key]["link"]}">Link</a>
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
