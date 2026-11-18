export interface TransportControl {
  url: string;
  authorization: string;
}

export interface TransportEndpoint {
  launchUrl: string;
  authorization?: string;
  name: string;
  scope?: string;
  route?: string;
  close: () => Promise<void>;
}
