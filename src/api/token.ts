export interface Token {
    readonly access_token:string;
    readonly expires_at:string;
    readonly expires_in:number;
    readonly refresh_token:string;
    readonly scope:string;
    readonly token_type:string;
    readonly user_id:string;
}