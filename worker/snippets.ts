export type Snippets = {
  url: string;
  markdown: string;
  html: string;
  org: string;
};

export function buildSnippets(url: string, title: string): Snippets {
  return {
    url,
    markdown: `![${title}](${url})`,
    html: `<img src='${url}' alt='${title}' />`,
    org: `[[img:${url}][${title}]]`,
  };
}
