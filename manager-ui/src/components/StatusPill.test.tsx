import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { StatusPill } from "./StatusPill";

describe("StatusPill", () => {
  it("renders the tone as a data attribute", () => {
    const html = renderToStaticMarkup(<StatusPill tone="ok">Running</StatusPill>);

    expect(html).toContain('data-tone="ok"');
    expect(html).toContain("Running");
  });
});
