// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`).
// There are various equivalent ways to declare your Docusaurus config.
// See: https://docusaurus.io/docs/api/docusaurus-config

import { themes as prismThemes } from 'prism-react-renderer';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/** @type {import('@docusaurus/types').Config} */
const config = {
	title: 'Odin Vulkan Guide',
	tagline: 'Practical guide to Vulkan graphics programming using Odin Language',
	favicon: 'img/favicon.ico',

	// Set the production url of your site here
	url: 'https://capati.github.io',
	// Set the /<baseUrl>/ pathname under which your site is served
	// For GitHub pages deployment, it is often '/<projectName>/'
	baseUrl: '/odin-vk-guide/',

	// GitHub pages deployment config.
	// If you aren't using GitHub pages, you don't need these.
	organizationName: 'Capati', // Usually your GitHub org/user name.
	projectName: 'odin-vk-guide', // Usually your repo name.

	onBrokenLinks: 'throw',
	onBrokenMarkdownLinks: 'warn',

	// Even if you don't use internationalization, you can use this field to set
	// useful metadata like html lang. For example, if your site is Chinese, you
	// may want to replace "en" with "zh-Hans".
	i18n: {
		defaultLocale: 'en',
		locales: ['en'],
	},

	plugins: [
		[require.resolve('docusaurus-lunr-search'), {
			indexBaseUrl: true,
			maxHits: 7,
			disableVersioning: true,
			excludeRoutes: [
				'/main/**/*',
			],
		}]
	],

	presets: [
		[
			'classic',
			/** @type {import('@docusaurus/preset-classic').Options} */
			({
				docs: {
					routeBasePath: '/',
					sidebarPath: './sidebars.js',
					// Please change this to your repo.
					// Remove this to remove the "edit this page" links.
					editUrl:
						'https://github.com/Capati/odin-vk-guide/website/',
				},
				blog: false,
				theme: {
					customCss: './src/css/custom.css',
				},
			}),
		],
	],

	themeConfig:
		/** @type {import('@docusaurus/preset-classic').ThemeConfig} */
		({
			// Replace with your project's social card
			image: 'img/docusaurus-social-card.jpg',
			docs: {
				sidebar: {
					hideable: true,
					autoCollapseCategories: true,
				},
			},
			navbar: {
				hideOnScroll: true,
				style: 'primary',
				title: 'vk.Guide',
				logo: {
					alt: 'Odin',
					src: 'img/logo.svg',
					target: '_self',
					width: 62,
				},
				items: [
					//   {
					//     type: 'docSidebar',
					//     sidebarId: 'tutorialSidebar',
					//     position: 'left',
					//     label: 'Tutorial',
					//   },
					// {to: '/blog', label: 'Blog', position: 'left'},
					{
						href: 'https://docs.vulkan.org/spec/latest/chapters/introduction.html#introduction',
						label: 'Vulkan Spec',
						position: 'right',
					},
					{
						href: 'https://github.com/Capati/odin-vk-guide',
						label: 'Tutorial Code',
						position: 'right',
					},
				],
			},
			footer: {
				style: 'dark',
				links: [
					{
						title: 'Community',
						items: [
							{
								label: 'Odin Programming Language',
								href: 'https://odin-lang.org/',
							},
							{
								label: 'Odin Discord',
								href: 'https://discord.gg/vafXTdubwr',
							},
							{
								label: 'Odin Forum',
								href: 'https://forum.odin-lang.org/',
							},
						],
					},
					{
						title: 'More',
						items: [
							{
								label: 'Vulkan Guide',
								href: 'https://vkguide.dev/',
							},
						],
					},
				],
				copyright: `Copyright © ${new Date().getFullYear()} Capati. Distributed by a <a target="_blank"
        rel="noopener noreferrer" href="https://github.com/just-the-docs/just-the-docs/blob/main/LICENSE.txt">MIT license</a>.`,
			},
			prism: {
				theme: prismThemes.github,
				darkTheme: prismThemes.dracula,
				additionalLanguages: ['odin', 'bash', 'glsl', 'hlsl'],
			},
		}),
};

export default config;
