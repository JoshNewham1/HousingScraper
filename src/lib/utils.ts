export const delay = (delayMs: number) => {
  return new Promise<void>((res, _) => {
    setTimeout(() => res(), delayMs);
  });
};

// Format the email HTML from the properties object
export const buildEmailHtml = (properties: any, subtitle: string) => {
  let emailHtml = `<h2>${subtitle}</h2>`;
  Object.keys(properties).forEach((key) => {
    emailHtml += `
    <div style="margin-bottom: 25px;">
      <a href="${properties[key]["link"]}">Link</a>
    `;

    Object.keys(properties[key])?.forEach((detail) => {
      if (detail === "link" || detail === "pricePerWeek") {
        // Skip link and weekly price attribs
        return;
      } else if (detail === "image") {
        emailHtml += `<p><b>${detail}:</b> <img src="${properties[key][detail]}" width="200"> </p>`;
        return;
      } else if (detail.includes("price")) {
        emailHtml += `<p><b>${detail}:</b> £${properties[key][detail]}</p>`;
        return;
      }
      emailHtml += `<p><b>${detail}:</b> ${properties[key][detail]}</p>`;
    });

    emailHtml += "</div><hr>";
  });
  return emailHtml;
};
